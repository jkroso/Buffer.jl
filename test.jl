#! jest
@require "." Buffer asyncpipe Take transform

macro blocks(e)
  quote
    t = @async $(esc(e))
    sleep(0)
    @test t.state == :runnable
  end
end

a = Buffer()
write(a, "a")
@test read(a, Char) == 'a'
@blocks read(a, Char)
@blocks eof(a)

testset("eof when written to then closed") do
  a = Buffer()
  t = @async eof(a)
  sleep(0)
  write(a, UInt8('a'))
  wait(t)
  @test t.result == false
  close(a)
  @test eof(a) == false
  @test isopen(a) == false
  @test read(a) == UInt8['a']
  @test eof(a) == true
end

testset("eof when closed immediatly after") do
  a = Buffer()
  t = @async eof(a)
  sleep(0)
  close(a)
  wait(t)
  @test t.result == true
end

take = asyncpipe(IOBuffer("abc"), Take(2))
@test !eof(take)
@test read(take) == b"ab"
@test eof(take)
skip(take, -1)
@test !eof(take)
@test read(take) == b"b"
@test eof(take)

testset("transform(fn, stream)") do
  in = IOBuffer("abc")
  out = transform(in) do in, out
    while !eof(in)
      write(out, readavailable(in))
    end
  end
  @test read(out) == b"abc"
end

testset("transform(fn, fn, stream)") do
  identity(in, out) = begin
    while !eof(in)
      write(out, readavailable(in))
    end
  end
  s = transform(identity, identity, Buffer())
  write(s, b"abc")
  @test isopen(s)
  close(s)
  @test !isopen(s)
  @test read(s) == b"abc"
end
