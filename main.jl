mutable struct AsyncBuffer <: IO
  ptr::UInt
  open::Bool
  onwrite::Condition
  data::Vector{UInt8}
end

AsyncBuffer() = AsyncBuffer(0, true, Condition(), UInt8[])

Base.write(io::AsyncBuffer, b::UInt8) = begin
  @assert io.open
  push!(io.data, b)
  notify(io.onwrite, true)
  1
end

Base.write(io::AsyncBuffer, b::Vector) = begin
  @assert io.open
  append!(io.data, b)
  notify(io.onwrite, false)
  length(b)
end

Base.isopen(io::AsyncBuffer) = io.open
Base.eof(io::AsyncBuffer) = begin
  io.ptr < length(io.data) && return false
  wait(io.onwrite)
end
Base.close(io::AsyncBuffer) = (io.open = false; notify(io.onwrite, true); nothing)
Base.nb_available(io::AsyncBuffer) = length(io.data) - io.ptr

Base.readavailable(io::AsyncBuffer) = begin
  nb_available(io) == 0 && wait(io.onwrite)
  out = io.data[io.ptr:end]
  io.ptr += length(out)
  out
end

Base.read(io::AsyncBuffer) = begin
  while isopen(io)
    wait(io.onwrite)
  end
  out = io.data[io.ptr+1:end]
  io.ptr += length(out)
  out
end

Base.read(io::AsyncBuffer, n::Integer) = begin
  while isopen(io) && nb_available(io) < n
    wait(io.onwrite)
  end
  @assert nb_available(io) >= n
  ptr = io.ptr
  io.ptr += n
  io.data[ptr+1:ptr+n]
end

Base.read(io::AsyncBuffer, ::Type{UInt8}) = begin
  @assert !eof(io)
  io.ptr += 1
  io.data[io.ptr]
end
