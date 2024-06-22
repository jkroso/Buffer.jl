@use "." AbstractBuffer @abstract @mutable

@abstract struct AbstractReadBuffer <: AbstractBuffer
  io::IO
end

"An wrapper that adds byte IO to any IO type"
@mutable ReadBuffer <: AbstractReadBuffer

Base.write(io::AbstractReadBuffer, b::UInt8) = write(io.io, b)
Base.read(io::AbstractReadBuffer, ::Type{UInt8}) = begin
  io.i < length(io.data) || pull!(io)
  @inbounds io.data[io.i+=1]
end

pull!(io::ReadBuffer) = begin
  bytes = eof(io.io) || readavailable(io.io)
  @assert bytes != true "Attempted to read from an empty IO"
  if ismarked(io)
    append!(io.data, bytes)
  else
    io.data = bytes
    io.i = 0
  end
end

Base.readavailable(io::AbstractReadBuffer) = begin
  if io.i < length(io.data)
    bytes = @view io.data[io.i+1:end]
    io.i = length(io.data)
    bytes
  else
    readavailable(io.io)
  end
end

Base.read(io::AbstractReadBuffer, n::Integer) = begin
  rem = length(io.data) - io.i
  if rem >= n
    bytes = @view io.data[io.i+1:io.i+n]
    io.i += n
    bytes
  else
    out = IOBuffer(maxsize=n)
    len = length(io.data)
    n -= write(out, @view io.data[io.i+1:len])
    io.i = len
    while n > 0
      n -= write(out, read(io.io, n))
    end
    take!(out)
  end
end

Base.read(io::AbstractReadBuffer) = begin
  rem = length(io.data) - io.i
  rem <= 0 && return eof(io.io) ? UInt8[] : read(io.io)
  eof(io.io) || append!(io.data, read(io.io))
  len = length(io.data)
  bytes = @view io.data[io.i+1:len]
  io.i = len
  bytes
end

Base.isopen(io::AbstractReadBuffer) = isopen(io.io)
Base.isreadable(io::AbstractReadBuffer) = isreadable(io.io)
Base.iswritable(io::AbstractReadBuffer) = iswritable(io.io)
Base.close(io::AbstractReadBuffer) = close(io.io)
Base.eof(io::AbstractReadBuffer) = io.i == length(io.data) && eof(io.io)
Base.bytesavailable(io::AbstractReadBuffer) = begin
  if io.i < length(io.data)
    length(io.data) - io.i
  else
    bytesavailable(io.io)
  end
end

Base.seek(io::AbstractReadBuffer, pos::Integer) = begin
  @assert pos >= 0 "Can't seek back that far"
  while pos >= length(io.data)
    bytes = eof(io.io) || readavailable(io.io)
    @assert bytes != true "Can't seek forward that far"
    append!(io.data, bytes)
  end
  io.i = pos
  io
end

"Wraps an input in a Buffer so that consumers can use the full IO interface"
buffer(io::T) where T<:IO = hasmethod(position, Tuple{T}) ? io : ReadBuffer(io)
buffer(x) = IOBuffer(x)
