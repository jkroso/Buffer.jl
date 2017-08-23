abstract type AsyncBuffer <: IO end

mutable struct Buffer <: AsyncBuffer
  ptr::UInt
  open::Bool
  onwrite::Condition
  data::Vector{UInt8}
end

Buffer() = Buffer(0, true, Condition(), UInt8[])

mutable struct Take <: AsyncBuffer
  limit::UInt
  ptr::UInt
  open::Bool
  onwrite::Condition
  data::Vector{UInt8}
end

Take(n) = Take(n, 0, true, Condition(), UInt8[])

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
Base.eof(io::Buffer) = nb_available(io) > 0 ? false : isopen(io) ? wait(io.onwrite) : true
Base.eof(io::Take) = nb_available(io) > 0 ? false : isopen(io) && io.ptr < io.limit ? wait(io.onwrite) : true
Base.close(io::AsyncBuffer) = (io.open = false; notify(io.onwrite, true); nothing)
Base.nb_available(io::Buffer) = length(io.data) - io.ptr
Base.nb_available(io::Take) = max(0, min(io.limit, length(io.data)) - io.ptr)

Base.readavailable(io::AsyncBuffer) = begin
  nb_available(io) == 0 && wait(io.onwrite)
  ptr = io.ptr
  io.ptr = ptr + nb_available(io)
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
  while isopen(io) && (io.ptr + nb_available(io)) < io.limit
    wait(io.onwrite)
  end
  start = io.ptr + 1
  io.ptr = io.limit
  io.data[start:io.limit]
end

Base.read(io::AsyncBuffer, n::Integer) = begin
  while isopen(io) && nb_available(io) < n
    wait(io.onwrite)
  end
  @assert nb_available(io) >= n
  ptr = io.ptr
  io.ptr += n
  io.data[ptr+1:io.ptr]
end

Base.read(io::AsyncBuffer, ::Type{UInt8}) = begin
  @assert !eof(io)
  io.ptr += 1
  io.data[io.ptr]
end

"Transfer data directly from one stream to another"
function asyncpipe(from::IO, to::IO)
  main_task = current_task()
  @schedule try
    write(to, from)
  catch e
    Base.throwto(main_task, e)
  end
  to
end
