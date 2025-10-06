using UniqueIDs
using Test
using Aqua: Aqua

Aqua.test_all(UniqueIDs)

function _assert_invariants_id2idx!(s::Gen)
    @assert length(s.idx_gens) ≤ typemax(UInt32)
    @assert s.gens_len ≤ length(s.idx_gens)
    @assert s.n_active ≤ s.gens_len
    @assert s.target_queue_length > 0
    @assert s.target_queue_length < typemax(Int32)
    @assert Int64(s.target_queue_length) + Int64(s.n_active) ≤ typemax(UInt32)
    n_inactive = count(isodd ∘ last, s.idx_gens)
    @assert n_inactive == length(s.idx_gens) - s.n_active
    # Check the free queue
    if iszero(n_inactive)
        @assert iszero(s.free_head)
        @assert iszero(s.free_tail)
    end
    visited = zeros(Bool, length(s.idx_gens))
    p = Int(s.free_head)
    n = 0
    while !iszero(p)
        @assert !visited[p]
        visited[p] = true
        n += 1
        next_p, gen = s.idx_gens[p]
        if p ≤ s.gens_len
            @assert isodd(gen)
        else
            @assert gen == typemax(UInt32)
        end
        # Unlike GenNoWrap gen is allowed to be typemax(UInt32)
        if iszero(next_p)
            @assert s.free_tail == p
        end
        p = next_p
    end
    @assert n == n_inactive
    nothing
end

#=
Don't add your tests to runtests.jl. Instead, create files named

    test-title-for-my-test.jl

The file will be automatically included inside a `@testset` with title "Title For My Test".
=#
for (root, dirs, files) in walkdir(@__DIR__)
    for file in files
        if isnothing(match(r"^test-.*\.jl$", file))
            continue
        end
        title = titlecase(replace(splitext(file[6:end])[1], "-" => " "))
        @testset "$title" begin
            include(file)
        end
    end
end
