include("main.jl")
using Base.Test

macro blocks(e)
  quote
    t = @schedule $(esc(e))
    sleep(0)
    @test t.state == :runnable
  end
end

a = Buffer()
write(a, "a")
@test read(a, Char) == 'a'
@blocks read(a, Char)
@blocks eof(a)

a=Buffer()
write(a, "abc")
@test readavailable(a) == b"abc"
@blocks eof(a)
close(a)
@test eof(a)

take = asyncpipe(IOBuffer("abc"), Take(2))
@test !eof(take)
@test read(take) == b"ab"
@test eof(take)
skip(take, -1)
@test !eof(take)
@test read(take) == b"b"
@test eof(take)
