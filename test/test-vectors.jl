using IDVectors
using IDVectors: assert_invariants, reset!
using Test

@testset "$idvector" for idvector in [
        IncIDVector,
        GenIDVector,
        GenNoWrapIDVector,
        DynIDVector,
    ]
    s = idvector()
    assert_invariants(s)
    id1 = next_id(s)
    @test id1 != 0
    @test isempty(s)
    @test length(s) == 0
    @test alloc_id!(s) == id1
    assert_invariants(s)
    @test !isempty(s)
    @test length(s) == 1
    id2 = next_id(s)
    @test alloc_id!(s) == id2
    assert_invariants(s)
    @test id1 != id2
    id3 = next_id(s)
    @test alloc_id!(s) == id3
    assert_invariants(s)
    @test id1 != id3

    q = copy(s)
    @test reset!(q) === q
    @test isempty(q)
    assert_invariants(q)
    @test next_id(q) == id1

    @testset "ways to delete" begin
        v = copy(s)
        @test pop!(v) == id3
        assert_invariants(v)
        @test v == [id1, id2]

        v = copy(s)
        @test popfirst!(v) == id1
        assert_invariants(v)
        @test v == [id2, id3]

        v = copy(s)
        @test empty!(v) === v
        assert_invariants(v)
        @test isempty(v)

        v = copy(s)
        @test free_id!(v, id1) === 1
        assert_invariants(v)
        @test v == [id3, id2]
        @test_throws KeyError free_id!(v, id1)
        @test_throws KeyError free_id!(v, Int64(0))
        @test free_id!(v, id2) === 2
        @test free_id!(v, id3) === 1

        v = copy(s)
        @test free_id!(v, id3) === 3
        assert_invariants(v)
        @test v == [id1, id2]

        v = copy(s)
        @test free_id!(v, id2) === 2
        assert_invariants(v)
        @test v == [id1, id3]

        @testset "popat!" begin
            v = copy(s)
            @test popat!(v, 1) === id1
            assert_invariants(v)
            @test v == [id2, id3]

            v = copy(s)
            @test popat!(v, 3) === id3
            assert_invariants(v)
            @test v == [id1, id2]

            v = copy(s)
            @test popat!(v, 2) === id2
            assert_invariants(v)
            @test v == [id1, id3]

            v = copy(s)
            @test_throws Exception popat!(v, 0)
            @test_throws Exception popat!(v, 4)
            assert_invariants(v)
            @test popat!(v, 0, "default") == "default"
            @test popat!(v, 4, "default") == "default"
            assert_invariants(v)
            @test v == [id1, id2, id3]
        end
        @testset "deleteat!" begin
            v = copy(s)
            @test deleteat!(v, 1) === v
            assert_invariants(v)
            @test v == [id2, id3]

            v = copy(s)
            @test deleteat!(v, 3) === v
            assert_invariants(v)
            @test v == [id1, id2]

            v = copy(s)
            @test deleteat!(v, 2) === v
            assert_invariants(v)
            @test v == [id1, id3]

            v = copy(s)
            @test_throws Exception deleteat!(v, 0)
            @test_throws Exception deleteat!(v, 4)
            assert_invariants(v)
            @test v == [id1, id2, id3]

            # Test deleting multiple indices
            v = copy(s)
            @test deleteat!(v, [1, 3]) === v
            assert_invariants(v)
            @test v == [id2]

            v = copy(s)
            @test deleteat!(v, 1:2) === v
            assert_invariants(v)
            @test v == [id3]

            # Test boolean mask
            v = copy(s)
            @test deleteat!(v, [true, false, true]) === v
            assert_invariants(v)
            @test v == [id2]

            v = copy(s)
            @test_throws Exception deleteat!(v, [true, false])  # wrong length boolean mask
            @test_throws Exception deleteat!(v, [3, 1])        # unsorted indices
            @test_throws Exception deleteat!(v, [1, 1])        # duplicate indices
            assert_invariants(v)
        end
        @testset "keepat!" begin
            init = idvector()
            ids = [alloc_id!(init) for i in 1:5]

            # Test boolean mask
            v = copy(init)
            @test keepat!(v, [true, false, true, true, true]) === v
            assert_invariants(v)
            @test v == [ids[1], ids[3], ids[4], ids[5]]

            v = copy(init)
            @test keepat!(v, [false, true, false, false, false]) === v
            assert_invariants(v)
            @test v == [ids[2],]

            v = copy(init)
            @test keepat!(v, [true, true, true, true, true]) === v
            assert_invariants(v)
            @test v == ids

            v = copy(init)
            @test keepat!(v, [false, false, false, false, false]) === v
            assert_invariants(v)
            @test isempty(v)

            # Test indices version
            v = copy(init)
            @test keepat!(v, [1, 3]) === v
            assert_invariants(v)
            @test v == [ids[1], ids[3]]

            v = copy(init)
            @test keepat!(v, 2:2) === v
            assert_invariants(v)
            @test v == [ids[2]]

            v = copy(init)
            @test keepat!(v, 1:3) === v
            assert_invariants(v)
            @test v == [ids[1], ids[2], ids[3]]

            v = copy(init)
            @test keepat!(v, Int[]) === v
            assert_invariants(v)
            @test isempty(v)

            # Test error conditions
            v = copy(init)
            @test_throws Exception keepat!(v, [true, false])  # wrong length boolean mask
            @test_throws Exception keepat!(v, [3, 1])        # unsorted indices
            @test_throws Exception keepat!(v, [1, 1])        # duplicate indices
            assert_invariants(v)
        end
        @testset "filter!" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]
            @test filter!(iseven, v) === v
            @test v == filter!(iseven, ids)
            assert_invariants(v)
        end
        @testset "swap_deleteat!" begin
            init = idvector()
            ids = [alloc_id!(init) for i in 1:5]  # ids[1] through ids[5]
            
            # Test single index deletion
            v = copy(init)
            @test swap_deleteat!(v, 1) === v
            assert_invariants(v)
            @test v == [ids[5], ids[2], ids[3], ids[4]]  # last element swapped to position 1
            @test v == swap_deleteat!(copy(ids), 1)
            
            v = copy(init)
            @test swap_deleteat!(v, 5) === v
            assert_invariants(v)
            @test v == [ids[1], ids[2], ids[3], ids[4]]  # last element removed, no swap needed
            @test v == swap_deleteat!(copy(ids), 5)
            
            v = copy(init)
            @test swap_deleteat!(v, 3) === v
            assert_invariants(v)
            @test v == [ids[1], ids[2], ids[5], ids[4]]  # last element swapped to position 3
            @test v == swap_deleteat!(copy(ids), 3)
            
            # Test bounds checking
            v = copy(init)
            @test_throws Exception swap_deleteat!(v, 0)
            @test_throws Exception swap_deleteat!(v, 6)
            assert_invariants(v)
            @test v == ids  # should be unchanged after error
            @test_throws Exception swap_deleteat!(copy(ids), 0)
            @test_throws Exception swap_deleteat!(copy(ids), 6)
            
            # Test multiple indices deletion
            v = copy(init)
            @test swap_deleteat!(v, [1, 3, 5]) === v
            assert_invariants(v)
            @test v == [ids[4], ids[2]]  # elements at positions 2 and 4 remain
            @test v == swap_deleteat!(copy(ids), [1,3,5])
            
            v = copy(init)
            @test swap_deleteat!(v, 1:3) === v
            assert_invariants(v)
            @test v == [ids[5], ids[4]]  # last two elements remain
            @test v == swap_deleteat!(copy(ids), 1:3)
            
            v = copy(init)
            @test swap_deleteat!(v, [2, 4]) === v
            assert_invariants(v)
            @test v == [ids[1], ids[5], ids[3]]  # elements at positions 1, 3, 5 remain
            @test v == swap_deleteat!(copy(ids), [2,4])
            
            # Test boolean mask
            v = copy(init)
            @test swap_deleteat!(v, [true, false, true, false, true]) === v
            assert_invariants(v)
            @test v == [ids[4], ids[2]]  # same result as [1, 3, 5]
            @test v == swap_deleteat!(copy(ids), [true, false, true, false, true])
            
            v = copy(init)
            @test swap_deleteat!(v, [false, true, false, true, false]) === v
            assert_invariants(v)
            @test v == [ids[1], ids[5], ids[3]]  # elements at positions 2, 4 deleted
            @test v == swap_deleteat!(copy(ids), [false, true, false, true, false])
            
            # Test error conditions
            v = copy(init)
            @test_throws Exception swap_deleteat!(v, [true, false])  # wrong length boolean mask
            @test_throws Exception swap_deleteat!(v, [3, 1])        # unsorted indices
            @test_throws Exception swap_deleteat!(v, [1, 1])        # duplicate indices
            assert_invariants(v)
            
            # Test edge cases
            v = copy(init)
            @test swap_deleteat!(v, Int[]) === v  # delete nothing
            assert_invariants(v)
            @test v == ids
            
            v = copy(init)
            @test swap_deleteat!(v, 1:5) === v  # delete everything
            assert_invariants(v)
            @test isempty(v)
        end
    end
    @testset "ways to reorder" begin
        @testset "permute!" begin
            # permute! doesn't check if the input is valid
            #  So don't test invalid permutations
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]

            perm = [2, 4, 3, 1, 5]
            permute!(v, perm)
            assert_invariants(v)
            @test v == ids[perm]
            permute!(ids, perm)
            @test v == ids
        end
        @testset "invpermute!" begin
            # invpermute! doesn't check if the input is valid
            #  So don't test invalid permutations
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]

            perm = [2, 4, 3, 1, 5]
            invpermute!(v, perm)
            assert_invariants(v)
            @test v == [ids[4], ids[1], ids[3], ids[2], ids[5]]
            invpermute!(ids, perm)
            @test v == ids
        end
        @testset "swap!" begin
            # Swap from UniqueVectors.jl
            "`swap!(uv::UniqueVector, to::Int, from::Int) -> uv` interchange/swap the values on the indices `to` and `from` in the `UniqueVector`"
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test swap!(v, 4, 4) === v
            @test_throws BoundsError swap!(v, 6, 6)
            @test_throws BoundsError swap!(v, 0, 0)
            @test_throws BoundsError swap!(v, 0, 1)
            @test_throws BoundsError swap!(v, 1, 0)
            @test v == ids
            assert_invariants(v)
            @test swap!(v, 1, 3) === v
            @test v == [ids[3], ids[2], ids[1], ids[4], ids[5]]
            @test v == swap!(copy(ids), 1, 3)
        end
    end
    @testset "accelerated ways to find" begin
        @testset "in" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test ids[1] ∈ v
            @test Int64(0) ∉ v
            free_id!(v, ids[1])
            @test ids[1] ∉ v
            alloc_id!(v)
            @test ids[1] ∉ v
            @test ids[2] ∈ v
        end
        @testset "count" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test count(isequal(ids[1]), v) == 1
            @test count(isequal(Int64(0)), v) == 0
            free_id!(v, ids[1])
            @test count(isequal(ids[1]), v) == 0
            alloc_id!(v)
            @test count(isequal(ids[1]), v) == 0
            @test count(isequal(ids[2]), v) == 1
        end
        @testset "id2idx" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test id2idx(v, ids[1]) === 1
            free_id!(v, ids[1])
            @test_throws KeyError id2idx(v, ids[1])
            @test id2idx(v, ids[5]) === 1
        end
        @testset "findfirst" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test findfirst(isequal(ids[1]), v) === 1
            free_id!(v, ids[1])
            @test findfirst(isequal(ids[1]), v) === nothing
            @test findfirst(isequal(ids[5]), v) === 1
        end
        @testset "findlast" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test findlast(isequal(ids[1]), v) === 1
            free_id!(v, ids[1])
            @test findlast(isequal(ids[1]), v) === nothing
            @test findlast(isequal(ids[5]), v) === 1
        end
        @testset "getindex" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test v[1] === ids[1]
            free_id!(v, ids[1])
            @test_throws BoundsError v[0]
            @test_throws BoundsError v[5]
            @test v[1] === ids[5]
        end
        @testset "indexin" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]
            free_id!(v, ids[1])
            alloc_id!(v)
            _ids = collect(v)
            @test isempty(indexin(Int64[], v))
            @test indexin(Int64[], v) == indexin(Int64[], _ids)
            @test indexin(Int64[0], v) == indexin(Int64[0], _ids)
            @test indexin([ids[1],ids[3],ids[5]], v) == indexin([ids[1],ids[3],ids[5]], _ids)
        end
        @testset "findnext" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test findnext(isequal(ids[1]), v, 1) === 1
            @test findnext(isequal(ids[1]), v, 2) === nothing
            free_id!(v, ids[1])
            @test findnext(isequal(ids[1]), v, 1) === nothing
            @test findnext(isequal(ids[5]), v, 1) === 1
            @test findnext(isequal(ids[5]), v, 2) === nothing
        end
        @testset "findprev" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test findprev(isequal(ids[3]), v, 1) === nothing
            @test findprev(isequal(ids[3]), v, 3) === 3
            free_id!(v, ids[1])
            @test findprev(isequal(ids[1]), v, 4) === nothing
            @test findprev(isequal(ids[5]), v, 1) === 1
            @test findprev(isequal(ids[5]), v, 0) === nothing
        end
        @testset "findall" begin
            v = idvector()
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            @test findall(isequal(ids[1]), v) == [1]
            free_id!(v, ids[1])
            @test findall(isequal(ids[1]), v) == []
            @test findall(isequal(ids[5]), v) == [1]
        end
    end
    @testset "unique" begin
        v = idvector()
        ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
        @test allunique(v)
        @test unique(v) !== v
        @test unique(v) == v
        @test unique(v) isa idvector
        @test unique!(v) === v
        @test v == ids
    end
    @testset "sizehint" begin
        for hint in [-10, -1, 0, 1, 2, 3, 4, 5, 6, 7, 10, 1000, 10000]
            v = idvector()
            sizehint!(v, hint)
            assert_invariants(v)
            ids = [alloc_id!(v) for i in 1:5]  # ids[1] through ids[5]
            assert_invariants(v)
        end
    end
end
