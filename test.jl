@use "github.com/jkroso/Rutherford.jl/test" @test testset
@use "." Buffer pipe

macro blocks(e)
  quote
    t = @async $(esc(e))
    sleep(0)
    @test t.state == :runnable
  end
end

testset("Buffer") do
  a = Buffer()
  write(a, "a")
  @test read(a, Char) == 'a'
  @blocks read(a, Char)
  @blocks eof(a)
end

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

testset("marks") do
  a = Buffer()
  write(a, ('a':'z')...)
  @test read(a, Char) == 'a'
  @test position(a) == 1
  mark(a)
  @test read(a, 3) == b"bcd"
  reset(a)
  @test read(a, 4) == b"bcde"
  skip(a, -2)
  @test read(a, 2) == b"de"
  skip(a, 2)
  @test read(a, 2) == b"hi"
  seek(a, 1)
  @test read(a, Char) == 'b'
  @test readavailable(a) == UInt8[('c':'z')...]
  write(a, ('1':'9')...)
  @test read(a, Char) == '1'
  close(a)
  @test read(a) == UInt8[('2':'9')...]
end

@use "./ReadBuffer.jl" ReadBuffer

testset("ReadBuffer") do
  input = PipeBuffer()
  write(input, "abcdefg")
  rb = ReadBuffer(input)
  @test !ismarked(rb)
  @test read(rb, 2) == b"ab"
  mark(rb)
  @test ismarked(rb)
  @test read(rb, Char) == 'c'
  @test read(rb, 2) == b"de"
  reset(rb)
  @test !ismarked(rb)
  @test read(rb, 3) == b"cde"
  skip(rb, -3)
  @test read(rb, 3) == b"cde"
  write(rb.io, "hi")
  @test read(rb) == b"fghi"
end
