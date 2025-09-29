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
    # test copy
    empty!(copy(s))
    @test !isempty(s)
    @test collect(copy(s)) == collect(s)
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

    # wrap around is allowed but should not be zero or violate uniqueness
    @testset "wrap around behavior" begin
        s = IncIDSet()
        s.next_id = -2
        IDVectors.assert_invariants(s)
        @test next_id(s) == -2
        @test alloc_id!(s) == -2
        IDVectors.assert_invariants(s)
        @test next_id(s) == -1
        @test alloc_id!(s) == -1
        IDVectors.assert_invariants(s)
        @test next_id(s) == 1
        @test alloc_id!(s) == 1
        IDVectors.assert_invariants(s)

        s = IncIDSet()
        s.next_id = -2
        push!(s.used_ids, Int64(1))
        IDVectors.assert_invariants(s)
        @test next_id(s) == -2
        @test alloc_id!(s) == -2
        @test next_id(s) == -1
        @test alloc_id!(s) == -1
        @test next_id(s) == 2
        @test alloc_id!(s) == 2
    end
end

@testset "GenIDSet" begin
    s = GenIDSet()
    IDVectors.assert_invariants(s)
    id1 = Int64(1)
    @test next_id(s) === id1
    @test isempty(s)
    @test length(s) == 0
    @test id1 ∉ s
    @test alloc_id!(s) === id1
    IDVectors.assert_invariants(s)
    @test collect(s) == [id1]
    @test length(s) == 1
    @test id1 ∈ s
    id2 = Int64(2)
    @test next_id(s) === id2
    @test alloc_id!(s) === id2
    IDVectors.assert_invariants(s)
    @test id2 ∈ s
    @test id1 ∈ s
    @test issetequal(collect(s), [id1, id2])
    @test length(s) == 2
    # test copy
    empty!(copy(s))
    @test !isempty(s)
    @test collect(copy(s)) == collect(s)
    free_id!(s, id1)
    IDVectors.assert_invariants(s)
    @test id1 ∉ s
    @test id2 ∈ s
    @test length(s) == 1
    @test collect(s) == [id2]
    free_id!(s, id2)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test length(s) == 0
    # idx 1 doesn't get reused yet
    id3 = Int64(3)
    @test next_id(s) === id3
    @test alloc_id!(s) === id3
    IDVectors.assert_invariants(s)
    @test collect(s) == [id3]
    empty!(s)
    @test isempty(s)
    @test next_id(s) === Int64(4)
    IDVectors.reset!(s)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test next_id(s) === id1

    # When we allocate enough new IDs, we should eventually reuse index 1
    # but with generation 1 (since generation increments when freed)
    # Let's allocate enough to trigger reuse
    used_ids = Int64[]
    for i in 1:(IDVectors.MIN_FREE_QUEUE_LEN+1)  # Force past MIN_FREE_QUEUE_LEN
        push!(used_ids, alloc_id!(s))
        free_id!(s, last(used_ids))
    end
    IDVectors.assert_invariants(s)
    @test used_ids == 1:(IDVectors.MIN_FREE_QUEUE_LEN+1)
    
    # Now allocate one more - this should reuse index 1 with generation 1
    reused_id = alloc_id!(s)
    IDVectors.assert_invariants(s)
    @test reused_id != id1  # Should be different due to generation increment
    @test (reused_id & 0xFFFFFFFF) == 1  # Index should be 1
    @test (reused_id >>> 32) == 2  # Generation should be 2
    @test reused_id ∈ s
    @test id1 ∉ s  # Original id1 should still not be in set
    @test collect(s) == [reused_id]

    # Test freeing the reused ID
    free_id!(s, reused_id)
    @test reused_id ∉ s
    IDVectors.assert_invariants(s)

    # Test empty!
    new_id2 = alloc_id!(s)
    @test (new_id2 & 0xFFFFFFFF) == 2  # Index should be 2
    @test (new_id2 >>> 32) == 2  # Generation should be 2
    @test length(s) == 1
    empty!(s)
    @test isempty(s)
    @test length(s) == 0
    @test reused_id ∉ s
    @test new_id2 ∉ s
    IDVectors.assert_invariants(s)

    # After empty!, next allocations should continue from where we left off
    # but with incremented generations for previously allocated indices
    next_id_after_empty = next_id(s)
    new_id3 = alloc_id!(s)
    @test (new_id3 & 0xFFFFFFFF) == 3  # Index should be 3
    @test (new_id3 >>> 32) == 2  # Generation should be 2
    @test new_id3 == next_id_after_empty
    @test new_id3 ∈ s
    IDVectors.assert_invariants(s)

    # Test KeyError on invalid free
    @test_throws KeyError free_id!(s, Int64(999999))
    @test_throws KeyError free_id!(s, Int64(0))
    IDVectors.assert_invariants(s)

    # Test sizehint!
    s_hint = GenIDSet()
    n_hint = 1000
    sizehint!(s_hint, n_hint)
    IDVectors.assert_invariants(s_hint)
    # After sizehint no allocations should be needed if the hinted capacity is never exceeded
    init_gens = s_hint.gens
    init_free_queue = s.free_queue
    for j in 1:10
        for i in 1:n_hint
            alloc_id!(s_hint)
        end
        empty!(s_hint)
        for i in 1:n_hint
            alloc_id!(s_hint)
        end
        for i in 1:10000
            free_id!(s_hint, first(s_hint))
            alloc_id!(s_hint)
        end
        empty!(s_hint)
    end
    @test init_gens === s_hint.gens
    @test init_free_queue === s.free_queue

    # Test generation-based ID structure
    @testset "Generation-based ID structure" begin
        s = GenIDSet()
        id = alloc_id!(s)
        
        # Extract index and generation
        index = id & 0xFFFFFFFF
        generation = (id >>> 32) # 32 bits for generation
        
        @test index == 1
        @test generation == 0
        
        # Free and verify we can't access it anymore
        free_id!(s, id)
        @test id ∉ s
        
        # The internal generation should now be odd (inactive)
        @test isodd(s.gens[index])
        IDVectors.assert_invariants(s)
    end

    # Test that overflow is handled appropriately
    @testset "Overflow handling" begin
        s = GenIDSet()
        # Set gens_len to maximum to test overflow
        s.gens_len = typemax(UInt32)
        s.n_active = typemax(UInt32)
        @test_throws OverflowError alloc_id!(s)
        @test_throws OverflowError next_id(s)

        # Set up s with high generations to simulate gen overflow
        s = GenIDSet()
        sizehint!(s, 10)
        s.gens_len = length(s.gens)
        s.gens .= Int64(2)^32-3
        s.free_write_head = length(s.gens)
        s.free_queue .= 1:length(s.free_queue)
        IDVectors.assert_invariants(s)
        for i in 1:s.gens_len
            @test alloc_id!(s) == (Int64(2)^32-2)<<32 | i
            free_id!(s, (Int64(2)^32-2)<<32 | i)
        end
        IDVectors.assert_invariants(s)
        for i in 1:s.gens_len - 1
            @test alloc_id!(s) == i
            free_id!(s, Int64(i))
        end
        IDVectors.assert_invariants(s)
        @test alloc_id!(s) == s.gens_len
        IDVectors.assert_invariants(s)
        empty!(s)
        IDVectors.assert_invariants(s)
    end
end

@testset "GenNoWrapIDSet" begin
    s = GenNoWrapIDSet()
    IDVectors.assert_invariants(s)
    id1 = Int64(1)
    @test next_id(s) === id1
    @test isempty(s)
    @test length(s) == 0
    @test id1 ∉ s
    @test alloc_id!(s) === id1
    IDVectors.assert_invariants(s)
    @test collect(s) == [id1]
    @test length(s) == 1
    @test id1 ∈ s
    id2 = Int64(2)
    @test next_id(s) === id2
    @test alloc_id!(s) === id2
    IDVectors.assert_invariants(s)
    @test id2 ∈ s
    @test id1 ∈ s
    @test issetequal(collect(s), [id1, id2])
    @test length(s) == 2
    # test copy
    empty!(copy(s))
    @test !isempty(s)
    @test collect(copy(s)) == collect(s)
    free_id!(s, id1)
    IDVectors.assert_invariants(s)
    @test id1 ∉ s
    @test id2 ∈ s
    @test length(s) == 1
    @test collect(s) == [id2]
    free_id!(s, id2)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test length(s) == 0
    # idx 2 get reused with gen 2 because of the free stack
    id3 = Int64(2)<<32 | Int64(2)
    @test next_id(s) === id3
    @test alloc_id!(s) === id3
    IDVectors.assert_invariants(s)
    @test collect(s) == [id3]
    empty!(s)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    # idx 2 get reused with gen 4 because of the free stack
    @test next_id(s) === Int64(4)<<32 | Int64(2)
    IDVectors.reset!(s)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test next_id(s) === id1

    # Test KeyError on invalid free
    @test_throws KeyError free_id!(s, Int64(999999))
    @test_throws KeyError free_id!(s, Int64(0))
    IDVectors.assert_invariants(s)

    # Test sizehint!
    s_hint = GenNoWrapIDSet()
    n_hint = 1000
    sizehint!(s_hint, n_hint)
    IDVectors.assert_invariants(s_hint)
    # After sizehint no allocations should be needed if the hinted capacity is never exceeded
    init_gens = s_hint.gens
    init_free_stack = s.free_stack
    for j in 1:10
        for i in 1:n_hint
            alloc_id!(s_hint)
        end
        empty!(s_hint)
        for i in 1:n_hint
            alloc_id!(s_hint)
        end
        for i in 1:10000
            free_id!(s_hint, first(s_hint))
            alloc_id!(s_hint)
        end
        empty!(s_hint)
    end
    @test init_gens === s_hint.gens
    @test init_free_stack === s.free_stack

    # Test that overflow is handled appropriately
    @testset "Overflow handling" begin
        s = GenNoWrapIDSet()
        # Set gens_len to maximum to test overflow
        s.gens_len = typemax(UInt32)
        s.n_active = typemax(UInt32)
        @test_throws OverflowError alloc_id!(s)
        @test_throws OverflowError next_id(s)

        # Set up s with high generations to simulate gen overflow
        s = GenNoWrapIDSet()
        sizehint!(s, 10)
        s.gens_len = length(s.gens)
        n = s.gens_len
        s.gens .= Int64(2)^32-3
        s.free_len = length(s.gens)
        s.free_stack .= 1:length(s.free_stack)
        IDVectors.assert_invariants(s)
        @test alloc_id!(s) == (Int64(2)^32-2)<<32 | n
        IDVectors.assert_invariants(s)
        free_id!(s, (Int64(2)^32-2)<<32 | n)
        IDVectors.assert_invariants(s)
        @test alloc_id!(s) == (Int64(2)^32-2)<<32 | n-1
        IDVectors.assert_invariants(s)
        free_id!(s, (Int64(2)^32-2)<<32 | n-1)
        IDVectors.assert_invariants(s)
        @test alloc_id!(s) == (Int64(2)^32-2)<<32 | n-2
        IDVectors.assert_invariants(s)
        empty!(s)
        IDVectors.assert_invariants(s)
    end
end

@testset "DynIDSet" begin
    s = DynIDSet()
    IDVectors.assert_invariants(s)
    id1 = Int64(1)
    @test next_id(s) === id1
    @test isempty(s)
    @test length(s) == 0
    @test id1 ∉ s
    @test alloc_id!(s) === id1
    IDVectors.assert_invariants(s)
    @test collect(s) == [id1]
    @test length(s) == 1
    @test id1 ∈ s
    id2 = Int64(2)
    @test next_id(s) === id2
    @test alloc_id!(s) === id2
    IDVectors.assert_invariants(s)
    @test id2 ∈ s
    @test id1 ∈ s
    @test issetequal(collect(s), [id1, id2])
    @test length(s) == 2
    # test copy
    empty!(copy(s))
    @test !isempty(s)
    @test collect(copy(s)) == collect(s)
    free_id!(s, id1)
    IDVectors.assert_invariants(s)
    @test id1 ∉ s
    @test id2 ∈ s
    @test length(s) == 1
    @test collect(s) == [id2]
    free_id!(s, id2)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test length(s) == 0
    id3 = Int64(3)
    @test next_id(s) === id3
    @test alloc_id!(s) === id3
    IDVectors.assert_invariants(s)
    @test collect(s) == [id3]
    empty!(s)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test next_id(s) === Int64(4)
    IDVectors.reset!(s)
    IDVectors.assert_invariants(s)
    @test isempty(s)
    @test next_id(s) === id1

    # Test KeyError on invalid free
    @test_throws KeyError free_id!(s, Int64(999999))
    @test_throws KeyError free_id!(s, Int64(0))
    IDVectors.assert_invariants(s)

    # Test sizehint!
    s = DynIDSet()
    n_hint = 1000
    sizehint!(s, n_hint)
    IDVectors.assert_invariants(s)
    # After sizehint no allocations should be needed if the hinted capacity is never exceeded
    init_slots = s.slots
    for j in 1:10
        for i in 1:n_hint
            alloc_id!(s)
            IDVectors.assert_invariants(s)
        end
        @assert s.n_active == n_hint
        empty!(s)
        IDVectors.assert_invariants(s)
        for i in 1:n_hint
            alloc_id!(s)
            IDVectors.assert_invariants(s)
        end
        for i in 1:10000
            free_id!(s, first(s))
            IDVectors.assert_invariants(s)
            alloc_id!(s)
            IDVectors.assert_invariants(s)
        end
        empty!(s)
    end
    @test length(init_slots) == length(s.slots)
    @test init_slots === s.slots

    # Test that overflow is handled appropriately
    @testset "Overflow handling" begin
        s = DynIDSet()
        s.next_id = -1
        IDVectors.assert_invariants(s)
        @test alloc_id!(s) == -1
        IDVectors.assert_invariants(s)
        # skips zero
        @test alloc_id!(s) == Int64(2)
        IDVectors.assert_invariants(s)
        empty!(s)
        IDVectors.assert_invariants(s)
    end
end
