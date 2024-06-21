"An wrapper that adds byte IO to any IO type"
mutable struct ReadBuffer <: IO
  io::IO
  buffer::Vector{UInt8}
  i::Int
  mark::Int
end

ReadBuffer(io) = ReadBuffer(io, UInt8[], 0, -1)

Base.write(io::ReadBuffer, b::UInt8) = write(io.io, b)
Base.read(io::ReadBuffer, ::Type{UInt8}) = begin
  io.i < length(io.buffer) || pull!(io)
  @inbounds io.buffer[io.i+=1]
end

pull!(io::ReadBuffer) = begin
  bytes = eof(io.io) || readavailable(io.io)
  @assert bytes != true "Attempted to read from an empty IO"
  if ismarked(io)
    append!(io.buffer, bytes)
  else
    io.buffer = bytes
    io.i = 0
  end
end

Base.readavailable(io::ReadBuffer) = begin
  if io.i < length(io.buffer)
    bytes = @view io.buffer[io.i+1:end]
    io.i = length(io.buffer)
    bytes
  else
    readavailable(io.io)
  end
end

Base.read(io::ReadBuffer, n::Integer) = begin
  rem = length(io.buffer) - io.i
  if rem >= n
    bytes = @view io.buffer[io.i+1:io.i+n]
    io.i += n
    bytes
  else
    out = IOBuffer(maxsize=n)
    len = length(io.buffer)
    n -= write(out, @view io.buffer[io.i+1:len])
    io.i = len
    while n > 0
      n -= write(out, read(io.io, n))
    end
    take!(out)
  end
end

Base.read(io::ReadBuffer) = begin
  rem = length(io.buffer) - io.i
  rem <= 0 && return eof(io.io) ? UInt8[] : read(io.io)
  eof(io.io) || append!(io.buffer, read(io.io))
  len = length(io.buffer)
  bytes = @view io.buffer[io.i+1:len]
  io.i = len
  bytes
end

Base.isopen(io::ReadBuffer) = isopen(io.io)
Base.isreadable(io::ReadBuffer) = isreadable(io.io)
Base.iswritable(io::ReadBuffer) = iswritable(io.io)
Base.close(io::ReadBuffer) = close(io.io)
Base.eof(io::ReadBuffer) = io.i == length(io.buffer) && eof(io.io)
Base.bytesavailable(io::ReadBuffer) = begin
  if io.i < length(io.buffer)
    length(io.buffer) - io.i
  else
    bytesavailable(io.io)
  end
end

Base.position(io::ReadBuffer) = io.i
Base.seek(io::ReadBuffer, pos::Integer) = begin
  @assert pos >= 0 "Can't seek back that far"
  while pos >= length(io.buffer)
    bytes = eof(io.io) || readavailable(io.io)
    @assert bytes != true "Can't seek forward that far"
    append!(io.buffer, bytes)
  end
  io.i = pos
  io
end
Base.skip(io::ReadBuffer, offset::Integer) = seek(io, position(io) + offset)

"Wraps an input in a Buffer so that consumers can use the full IO interface"
buffer(io::T) where T<:IO = hasmethod(position, Tuple{T}) ? io : ReadBuffer(io)
buffer(x) = IOBuffer(x)
