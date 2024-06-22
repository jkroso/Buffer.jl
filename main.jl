@use "github.com/jkroso/Prospects.jl" @abstract @mutable

@abstract struct AbstractBuffer <: IO
  i::Int=0
  mark::Int=-1
  data::Vector{UInt8}=UInt8[]
end

@abstract struct AsyncBuffer <: AbstractBuffer
  open::Bool=true
  onwrite::Condition=Condition()
end

@mutable Buffer <: AsyncBuffer

Buffer(buf::Vector{UInt8}) = Buffer(true, Condition(), 0, -1, buf)

Base.write(io::AsyncBuffer, b::UInt8) = begin
  @assert io.open
  push!(io.data, b)
  notify(io.onwrite, false)
  1
end

Base.write(io::AsyncBuffer, b::Vector{UInt8}) = begin
  @assert io.open
  append!(io.data, b)
  notify(io.onwrite, false)
  length(b)
end

Base.isopen(io::AsyncBuffer) = io.open
Base.eof(io::AsyncBuffer) = bytesavailable(io) > 0 ? false : isopen(io) ? wait(io.onwrite) : true
Base.close(io::AsyncBuffer) = (io.open = false; notify(io.onwrite, true); nothing)
Base.bytesavailable(io::AbstractBuffer) = length(io.data) - io.i

Base.readavailable(io::AbstractBuffer) = begin
  i = io.i
  bytes = i > 0 ? @view(io.data[i+1:end]) : io.data
  ismarked(io) || clear!(io)
  bytes
end

clear!(io::AbstractBuffer) = begin
  io.data = UInt8[]
  io.i = 0
end

Base.read(io::AsyncBuffer) = begin
  while isopen(io); wait(io.onwrite) end
  bytes = @view io.data[io.i+1:end]
  io.i = length(io.data)
  bytes
end

Base.read(io::AsyncBuffer, n::Integer) = begin
  while isopen(io) && bytesavailable(io) < n; wait(io.onwrite) end
  @assert bytesavailable(io) >= n
  ptr = io.i
  io.i += n
  @view io.data[ptr+1:io.i]
end

Base.read(io::AbstractBuffer, ::Type{UInt8}) = begin
  @assert !eof(io)
  @inbounds io.data[io.i+=1]
end

Base.position(io::AbstractBuffer) = io.i
Base.skip(io::AbstractBuffer, n::Integer) = seek(io, io.i + n)
Base.seek(io::AsyncBuffer, pos::Integer) = begin
  @assert pos >= 0 "Can't seek back that far"
  while !eof(io) && pos > length(io.data); wait(io.onwrite) end
  @assert pos <= length(io.data) "Can't seek forward that far"
  io.i = pos
  io
end

"Pass data down a chain of IO's. Closing each one on completion of it's input"
pipe(from::IO, to::IO, rest...) = foldl(pipe, rest, init=pipe(from, to))
pipe(from::IO, to::IO) = begin
  write(to, from)
  close(to)
  to
end
