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

pull!(io::AbstractReadBuffer) = begin
  bytes = pull(io)
  if ismarked(io) || io.i < length(io.data)
    append!(io.data, bytes)
  else
    io.data = bytes
    io.i = 0
  end
  length(bytes)
end

buffer!(io::AbstractReadBuffer) = begin
  @assert !eof(io.io) "Attempted to read from an empty IO"
  bytes = pull(io)
  append!(io.data, bytes)
  length(bytes)
end

"""
Read data from the input stream and optionally transform it before returning it.

This is likely the only method you will need to define for any subtype of `AbstractReadBuffer`
"""
pull(io::ReadBuffer) = readavailable(io.io)

Base.readavailable(io::AbstractReadBuffer) = begin
  if io.i < length(io.data)
    bytes = @view io.data[io.i+1:end]
    io.i = length(io.data)
    bytes
  else
    pull(io)
  end
end

Base.read(io::AbstractReadBuffer, n::Integer) = begin
  rem = length(io.data) - io.i
  while rem < n; rem += pull!(io) end
  bytes = @view io.data[io.i+1:io.i+n]
  io.i += n
  bytes
end

Base.read(io::AbstractReadBuffer) = begin
  while !eof(io.io); buffer!(io) end
  len = length(io.data)
  bytes = @view io.data[io.i+1:len]
  io.i = len
  bytes
end

Base.read(io::ReadBuffer) = begin
  rem = length(io.data) - io.i
  rem <= 0 && return eof(io.io) ? UInt8[] : read(io.io)
  invoke(read, Tuple{AbstractReadBuffer}, io)
end

Base.isopen(io::AbstractReadBuffer) = isopen(io.io)
Base.isreadable(io::AbstractReadBuffer) = isreadable(io.io)
Base.iswritable(io::AbstractReadBuffer) = iswritable(io.io)
Base.close(io::AbstractReadBuffer) = close(io.io)
Base.eof(io::AbstractReadBuffer) = io.i == length(io.data) && eof(io.io)
Base.bytesavailable(io::AbstractReadBuffer) = length(io.data) - io.i
Base.bytesavailable(io::ReadBuffer) = begin
  if io.i < length(io.data)
    length(io.data) - io.i
  else
    bytesavailable(io.io)
  end
end

Base.seek(io::AbstractReadBuffer, pos::Integer) = begin
  @assert pos >= 0 "Can't seek back that far"
  while length(io.data) < pos; buffer!(io) end
  io.i = pos
  io
end

"Wraps an input in a Buffer so that consumers can use the full IO interface"
buffer(io::T) where T<:IO = hasmethod(position, Tuple{T}) ? io : ReadBuffer(io)
buffer(x) = IOBuffer(x)
