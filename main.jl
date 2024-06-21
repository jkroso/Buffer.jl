abstract type AbstractBuffer <: IO end

mutable struct Buffer <: AbstractBuffer
  ptr::Int
  open::Bool
  onwrite::Condition
  mark::Int
  data::Vector{UInt8}
end

Buffer() = Buffer(UInt8[])
Buffer(buf::Vector{UInt8}) = Buffer(0, true, Condition(), -1, buf)

Base.write(io::AbstractBuffer, b::UInt8) = begin
  @assert io.open
  push!(io.data, b)
  notify(io.onwrite, false)
  1
end

Base.write(io::AbstractBuffer, b::Vector{UInt8}) = begin
  @assert io.open
  append!(io.data, b)
  notify(io.onwrite, false)
  length(b)
end

Base.isopen(io::AbstractBuffer) = io.open
Base.eof(io::Buffer) = bytesavailable(io) > 0 ? false : isopen(io) ? wait(io.onwrite) : true
Base.close(io::AbstractBuffer) = (io.open = false; notify(io.onwrite, true); nothing)
Base.bytesavailable(io::Buffer) = length(io.data) - io.ptr

Base.readavailable(io::AbstractBuffer) = begin
  ptr = io.ptr
  bytes = ptr > 0 ? @view(io.data[ptr+1:end]) : io.data
  ismarked(io) || clear!(io)
  bytes
end

clear!(io::AbstractBuffer) = begin
  io.data = UInt8[]
  io.ptr = 0
end

Base.read(io::AbstractBuffer) = begin
  while isopen(io); wait(io.onwrite) end
  bytes = @view io.data[io.ptr+1:end]
  io.ptr = length(io.data)
  bytes
end

Base.read(io::AbstractBuffer, n::Integer) = begin
  while isopen(io) && bytesavailable(io) < n; wait(io.onwrite) end
  @assert bytesavailable(io) >= n
  ptr = io.ptr
  io.ptr += n
  @view io.data[ptr+1:io.ptr]
end

Base.read(io::AbstractBuffer, ::Type{UInt8}) = begin
  @assert !eof(io)
  @inbounds io.data[io.ptr+=1]
end

Base.position(io::AbstractBuffer) = io.ptr
Base.skip(io::AbstractBuffer, n::Integer) = seek(io, position(io) + n)
Base.seek(io::AbstractBuffer, pos::Integer) = begin
  @assert pos >= 0 "Can't seek back that far"
  while !eof(io) && pos > length(io.data); wait(io.onwrite) end
  @assert pos <= length(io.data) "Can't seek forward that far"
  io.ptr = pos
  io
end

"Pass data down a chain of IO's. Closing each one on completion of it's input"
pipe(from::IO, to::IO, rest...) = foldl(pipe, rest, init=pipe(from, to))
pipe(from::IO, to::IO) = begin
  write(to, from)
  close(to)
  to
end
