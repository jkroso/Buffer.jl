abstract type AsyncBuffer <: IO end

mutable struct Buffer <: AsyncBuffer
  ptr::Int
  open::Bool
  onwrite::Condition
  data::Vector{UInt8}
end

Buffer() = Buffer(0, true, Condition(), UInt8[])

mutable struct Take <: AsyncBuffer
  limit::Int
  ptr::Int
  open::Bool
  onwrite::Condition
  data::Vector{UInt8}
end

Take(n) = Take(n, 0, true, Condition(), UInt8[])

Base.write(io::AsyncBuffer, b::UInt8) = begin
  @assert io.open
  push!(io.data, b)
  notify(io.onwrite, false)
  1
end

Base.write(io::AsyncBuffer, b::Vector) = begin
  @assert io.open
  append!(io.data, b)
  notify(io.onwrite, false)
  length(b)
end

Base.isopen(io::AsyncBuffer) = io.open
Base.eof(io::Buffer) = bytesavailable(io) > 0 ? false : isopen(io) ? wait(io.onwrite) : true
Base.eof(io::Take) = bytesavailable(io) > 0 ? false : isopen(io) && io.ptr < io.limit ? wait(io.onwrite) : true
Base.close(io::AsyncBuffer) = (io.open = false; notify(io.onwrite, true); nothing)
Base.bytesavailable(io::Buffer) = length(io.data) - io.ptr
Base.bytesavailable(io::Take) = max(0, min(io.limit, length(io.data)) - io.ptr)

Base.readavailable(io::AsyncBuffer) = begin
  bytesavailable(io) == 0 && wait(io.onwrite)
  ptr = io.ptr
  io.ptr = ptr + bytesavailable(io)
  io.data[ptr+1:io.ptr]
end

Base.read(io::AsyncBuffer) = begin
  while isopen(io)
    wait(io.onwrite)
  end
  start = io.ptr + 1
  io.ptr = length(io.data)
  io.data[start:end]
end

Base.read(io::Take) = begin
  while isopen(io) && (io.ptr + bytesavailable(io)) < io.limit
    wait(io.onwrite)
  end
  start = io.ptr + 1
  io.ptr = io.limit
  io.data[start:io.limit]
end

Base.read(io::AsyncBuffer, n::Integer) = begin
  while isopen(io) && bytesavailable(io) < n
    wait(io.onwrite)
  end
  @assert bytesavailable(io) >= n
  ptr = io.ptr
  io.ptr += n
  io.data[ptr+1:io.ptr]
end

Base.read(io::AsyncBuffer, ::Type{UInt8}) = begin
  @assert !eof(io)
  io.ptr += 1
  io.data[io.ptr]
end

Base.skip(io::AsyncBuffer, n) = io.ptr = max(0, min(io.ptr + n, length(io.data)))

"""
Write all data from stream `a` onto stream `b` then close stream `b`. Presumably
stream `b` will be transforming the data that's written to it
"""
pipe(from::IO, to::IO) = transform(identity_transform, from, out=to)
identity_transform(in, out) = write(out, in)

"""
Produces a new stream and passes it to `fn`. Which will read data from the input
stream and write it to the newly created output stream

```
# The identity transform but with logging
transform(IOBuffer("abc")) do in, out
  while !eof(in)
    write(out, @show(readavailable(in)))
  end
end
```
"""
transform(fn, stream; out=Buffer()) = begin
  main_task = current_task()
  @async try
    fn(stream, out)
  catch e
    Base.throwto(main_task, e)
  finally
    close(out)
  end
  out
end

"""
Wrap a stream such that both its input and output sides can be transformed
"""
transform(in_transform, out_transform, stream) = begin
  duplex = Duplex()
  transform(in_transform, duplex.in, out=stream)
  transform(out_transform, stream, out=duplex.out)
  duplex
end

struct Duplex <: IO
  in::Buffer
  out::Buffer
end
Duplex() = Duplex(Buffer(), Buffer())
Base.write(d::Duplex, data::Union{Vector,Char,UInt8,Base.CodeUnits{UInt8,String}}) = write(d.in, data)
Base.read(d::Duplex, T) = read(d.out, T)
Base.read(d::Duplex) = read(d.out)
Base.bytesavailable(d::Duplex) = bytesavailable(d.out)
Base.readavailable(d::Duplex) = readavailable(d.out)
Base.isopen(d::Duplex) = isopen(d.in)
Base.close(d::Duplex) = close(d.in)
Base.eof(d::Duplex) = eof(d.out)
