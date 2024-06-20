"An wrapper that adds byte IO to any IO type"
mutable struct ReadBuffer <: IO
  io::IO
  buffer::Vector{UInt8}
  i::Int
end

ReadBuffer(io) = ReadBuffer(io, UInt8[], 0)

Base.write(io::ReadBuffer, b::UInt8) = write(io.io, b)
Base.read(io::ReadBuffer, ::Type{UInt8}) = begin
  if io.i < length(io.buffer)
    io.buffer[io.i+=1]
  else
    io.buffer = readavailable(io.io)
    if isempty(io.buffer)
      io.buffer = read(io.buffer, 1)
    end
    io.i = 1
    io.buffer[1]
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

Base.isopen(io::ReadBuffer) = isopen(io.io)
Base.isreadable(io::ReadBuffer) = bytesavailable(io) > 0
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
