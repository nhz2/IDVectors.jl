# Keep the free_queue with this many entries to avoid the
# generation wrapping around too often
const MIN_FREE_QUEUE_LEN = 2^16-1

"""
The 32 most significant bits of an id is the generation. Even generations are active, odd generations are inactive.
The 32 least significant bits of an id is an index.
id's are never zero.
IDs may wrap around after about 2^47 pairs of alloc and free.
"""
mutable struct Gen <: UniqueID
    ids::Memory{Int64}
    idx_gens::Memory{NTuple{2, UInt32}}
    gens_len::UInt32
    n_active::UInt32
    # free_head and free_tail are the ends of a free link list queue 
    # in the inactive idx slots in idx_gens
    free_head::UInt32
    free_tail::UInt32
    # Keeping a large free queue reduces the frequency of reusing old ids
    target_queue_length::Int
end

function Gen()
    Gen(
        Memory{Int64}(undef,0),
        Memory{NTuple{2, UInt32}}(undef, 0),
        UInt32(0),
        UInt32(0),
        UInt32(0),
        UInt32(0),
        MIN_FREE_QUEUE_LEN,
    )
end

function reset!(s::Gen)::Gen
    s.ids = Memory{Int64}(undef,0)
    s.idx_gens = Memory{NTuple{2, UInt32}}(undef, 0)
    s.gens_len = UInt32(0)
    s.n_active = UInt32(0)
    s.free_head = UInt32(0)
    s.free_tail = UInt32(0)
    s.target_queue_length = MIN_FREE_QUEUE_LEN
    s
end

function Base.copy(s::Gen)
    Gen(
        copy(s.ids),
        copy(s.idx_gens),
        s.gens_len,
        s.n_active,
        s.free_head,
        s.free_tail,
        s.target_queue_length,
    )
end

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

function next_id(s::Gen)::Int64
    n_active = s.n_active
    if n_active ≥ typemax(UInt32) - s.target_queue_length
        throw(OverflowError("next_id would wraparound"))
    end
    if iszero(s.free_head)
        Int64(length(s.idx_gens) + 1)
    else
        @inbounds new_gen = last(s.idx_gens[s.free_head]) + UInt32(1)
        Int64(new_gen)<<32 | Int64(s.free_head)
    end
end

function _grow_free_queue!(s::Gen, n::Int64)
    n = n + s.target_queue_length
    old_mem = s.idx_gens
    old_len = length(old_mem)
    if n > old_len
        new_size = Int(min(overallocation(n), Int64(typemax(UInt32))))
        new_mem = typeof(old_mem)(undef, new_size)
        unsafe_copyto!(new_mem, 1, old_mem, 1, old_len)
        # fill out the free queue
        if !iszero(s.free_tail)
            @inbounds new_mem[s.free_tail] = (UInt32(old_len + 1), last(new_mem[s.free_tail]))
        end
        for i in old_len + 1 : new_size - 1
            @inbounds new_mem[i] = (UInt32(i+1), typemax(UInt32))
        end
        @inbounds new_mem[end] = (UInt32(0), typemax(UInt32))
        if iszero(s.free_head)
            s.free_head = UInt32(old_len + 1)
        end
        s.free_tail = UInt32(new_size)
        s.idx_gens = new_mem
    end
end

function alloc_id!(s::Gen)::Int64
    n_active = s.n_active
    if s.target_queue_length ≥ typemax(UInt32) - n_active
        throw(OverflowError("next_id would wraparound"))
    end
    idx = n_active + UInt32(1)
    _grow_field!(s, Int64(idx), :ids)
    _grow_free_queue!(s, Int64(idx))
    if s.free_head > s.gens_len
        s.gens_len = s.free_head
    end
    @inbounds next_p, old_gen = s.idx_gens[s.free_head]
    new_gen = old_gen + UInt32(1)
    id = Int64(new_gen)<<32 | Int64(s.free_head)
    @inbounds s.idx_gens[s.free_head] = (idx, new_gen)
    @inbounds s.ids[idx] = id
    s.n_active += UInt32(1)
    s.free_head = next_p
    id
end

function _pop_id2idx!(s::Gen, id::Int64)::Int
    if id ∉ s
        throw(KeyError(id))
    end
    gidx = id%UInt32
    gen = (id>>>32)%UInt32
    @inbounds idx, storedgen = s.idx_gens[gidx]
    @inbounds s.idx_gens[s.free_tail] = (gidx, last(s.idx_gens[s.free_tail]))
    s.free_tail = gidx
    @inbounds s.idx_gens[gidx] = (UInt32(0), gen + UInt32(1))
    s.n_active -= UInt32(1)
    idx
end

Base.@propagate_inbounds function _set_id2idx!(s::Gen, idx::Int, id::Int64)::Nothing
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    gidx = id%UInt32
    gen = (id>>>32)%UInt32
    @inbounds s.idx_gens[gidx] = (idx, gen)
    nothing
end


function Base.size(s::Gen)
    (Int(s.n_active),)
end

function Base.in(id::Int64, s::Gen)::Bool
    idx = id%UInt32
    gen = (id>>>32)%UInt32
    if isodd(gen)
        return false
    end
    if iszero(idx)
        return false
    end
    if idx > s.gens_len
        return false
    end
    @inbounds saved_gen = last(s.idx_gens[idx])
    if saved_gen != gen
        return false
    end
    return true
end

Base.@propagate_inbounds function id2idx(s::Gen, id::Int64)::Int
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    idx = id%UInt32
    @inbounds first(s.idx_gens[idx])
end

function Base.empty!(s::Gen)::Gen
    n = s.gens_len
    for gidx in UInt32(1):n
        @inbounds idx, gen = s.idx_gens[gidx]
        if iseven(gen)
            @inbounds s.idx_gens[s.free_tail] = (gidx, last(s.idx_gens[s.free_tail]))
            s.free_tail = gidx
            @inbounds s.idx_gens[gidx] = (UInt32(0), gen + UInt32(1))
        end
    end
    s.n_active = UInt32(0)
    s
end

function _sizehint_id2idx!(s::Gen, n; kwargs...)
    if n > typemax(UInt32) - s.target_queue_length
        throw(OverflowError("next_id would wraparound"))
    end
    _n = max(n, 0)%Int64
    _grow_free_queue!(s, _n)
    nothing
end
