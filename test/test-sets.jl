using IDVectors
using Test

@testset "IncIDSet" begin
    s = IncIDSet()
    id1 = Int64(1)
    @test next_id(s) === id1
    @test isempty(s)
    @test length(s) == 0
    @test id1 ∉ s
    @test alloc_id!(s) === id1
    @test collect(s) == [id1]
    @test length(s) == 1
    @test id1 ∈ s
    id2 = Int64(2)
    @test next_id(s) === id2
    @test alloc_id!(s) === id2
    @test id2 ∈ s
    @test id1 ∈ s
    @test issetequal(collect(s), [id1, id2])
    @test length(s) == 2
    free_id!(s, id1)
    @test id1 ∉ s
    @test id2 ∈ s
    @test length(s) == 1
    @test collect(s) == [id2]
    free_id!(s, id2)
    @test isempty(s)
    @test length(s) == 0
    id3 = Int64(3)
    @test next_id(s) === id3
    @test alloc_id!(s) === id3
    @test collect(s) == [id3]
    empty!(s)
    @test isempty(s)
    @test next_id(s) === Int64(4)
    IDVectors.reset!(s)
    @test isempty(s)
    @test next_id(s) === id1
end
