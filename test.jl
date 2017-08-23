include("main.jl")
using Base.Test

macro blocks(e)
  quote
    t = @schedule $(esc(e))
    sleep(0)
    @test t.state == :runnable
  end
end

a = AsyncBuffer()
write(a, "a")
@test read(a, Char) == 'a'
@blocks read(a, Char)
@blocks eof(a)

a = AsyncBuffer()
t = @schedule eof(a) == true
close(a)
@test t.result == true
