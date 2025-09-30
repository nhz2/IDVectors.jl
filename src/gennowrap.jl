"""
The 32 most significant bits of an id is the generation. Even generations are active, odd generations are inactive.
The 32 least significant bits of an id is an index.
id's are never zero.
IDs never wrap around but 8 bytes are leaked every 2^31 pairs of alloc and free.
"""
mutable struct GenNoWrap <: UniqueID
    ids::Memory{Int64}
    idx_gens::Memory{NTuple{2, UInt32}}
    gens_len::UInt32
    n_active::UInt32
    # The free stack is stored in a link list in free idx spots in idx_gens
    # This is zero if the free stack is empty
    free_head::UInt32
end

function GenNoWrap()
    GenNoWrap(
        Memory{Int64}(undef,0),
        Memory{NTuple{2, UInt32}}(undef, 0),
        UInt32(0),
        UInt32(0),
        UInt32(0),
    )
end

function reset!(s::GenNoWrap)::GenNoWrap
    s.ids = Memory{Int64}(undef,0)
    s.idx_gens = Memory{NTuple{2, UInt32}}(undef, 0)
    s.gens_len = UInt32(0)
    s.n_active = UInt32(0)
    s.free_head = UInt32(0)
    s
end

function Base.copy(s::GenNoWrap)
    GenNoWrap(
        copy(s.ids),
        copy(s.idx_gens),
        s.gens_len,
        s.n_active,
        s.free_head,
    )
end

function _assert_invariants_id2idx!(s::GenNoWrap)
    @assert length(s.idx_gens) ≤ typemax(UInt32)
    @assert s.gens_len ≤ length(s.idx_gens)
    @assert s.n_active ≤ s.gens_len
    n_free = 0
    n_dead = 0
    for (gidx, (idx, gen)) in enumerate(view(s.idx_gens, 1:s.gens_len))
        if isodd(gen)
            if gen == typemax(UInt32)
                n_dead += 1
                # canonical dead slot
                @assert idx == typemax(UInt32)
            else
                n_free += 1
            end
        end
    end
    @assert s.gens_len == n_dead + n_free + s.n_active
    # Finally check the free stack
    visited = zeros(Bool, s.gens_len)
    p = Int(s.free_head)
    n = 0
    while !iszero(p)
        @assert p ≤ s.gens_len
        @assert !visited[p]
        visited[p] = true
        n += 1
        p, gen = s.idx_gens[p]
        @assert isodd(gen)
        @assert gen != typemax(UInt32)
    end
    @assert n == n_free
    nothing
end

function next_id(s::GenNoWrap)::Int64
    gens_len = s.gens_len
    free_head = s.free_head
    if iszero(free_head)
        # No free slots make a new one with generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        Int64(gens_len + UInt32(1))
    else
        # Pick a slot off the free queue
        @inbounds new_gen = last(s.idx_gens[free_head]) + UInt32(1)
        Int64(new_gen)<<32 | Int64(free_head)
    end
end

function alloc_id!(s::GenNoWrap)::Int64
    n_active = s.n_active
    if n_active == typemax(UInt32)
        throw(OverflowError("next_id would wraparound"))
    end
    idx = n_active + UInt32(1)
    _grow_field!(s, Int64(idx), :ids)
    gens_len = s.gens_len
    free_head = s.free_head
    id = if iszero(free_head)
        # No free slots make a new one with generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        _grow_field!(s, Int64(gens_len + UInt32(1)), :idx_gens, Int64(typemax(UInt32)))
        s.gens_len += UInt32(1)
        @inbounds s.idx_gens[s.gens_len] = (idx, UInt32(0))
        s.n_active += UInt32(1)
        Int64(s.gens_len)
    else
        # Pick a slot off the free queue
        @inbounds next_free_head, free_gen = s.idx_gens[free_head]
        new_gen = free_gen + UInt32(1)
        @inbounds s.idx_gens[free_head] = (idx, new_gen)
        s.free_head = next_free_head
        s.n_active += UInt32(1)
        Int64(new_gen)<<32 | Int64(free_head)
    end
    @inbounds s.ids[idx] = id
    id
end

function _pop_id2idx!(s::GenNoWrap, id::Int64)::Int
    if id ∉ s
        throw(KeyError(id))
    end
    gidx = id%UInt32
    gen = (id>>>32)%UInt32
    new_gen = gen + UInt32(1)
    @inbounds idx, storedgen = s.idx_gens[gidx]
    if new_gen != typemax(UInt32)
        @inbounds s.idx_gens[gidx] = (s.free_head, new_gen)
        s.free_head = gidx
    else
        @inbounds s.idx_gens[gidx] = (~UInt32(0), new_gen)
    end
    s.n_active -= UInt32(1)
    idx
end

Base.@propagate_inbounds function _set_id2idx!(s::GenNoWrap, idx::Int, id::Int64)::Nothing
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    gidx = id%UInt32
    gen = (id>>>32)%UInt32
    @inbounds s.idx_gens[gidx] = (idx, gen)
    nothing
end

function Base.size(s::GenNoWrap)
    (Int(s.n_active),)
end

function Base.in(id::Int64, s::GenNoWrap)::Bool
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

Base.@propagate_inbounds function id2idx(s::GenNoWrap, id::Int64)::Int
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    idx = id%UInt32
    @inbounds first(s.idx_gens[idx])
end

function Base.empty!(s::GenNoWrap)::GenNoWrap
    n = s.gens_len
    for gidx in UInt32(1):n
        @inbounds idx, gen = s.idx_gens[gidx]
        if iseven(gen)
            new_gen = gen + UInt32(1)
            if new_gen != typemax(UInt32)
                @inbounds s.idx_gens[gidx] = (s.free_head, new_gen)
                s.free_head = gidx
            else
                @inbounds s.idx_gens[gidx] = (~UInt32(0), new_gen)
            end
        end
    end
    s.n_active = UInt32(0)
    s
end

function _sizehint_id2idx!(s::GenNoWrap, n; kwargs...)
    if n > typemax(UInt32)
        throw(OverflowError("next_id would wraparound"))
    end
    _n = max(n, 0)%Int64
    _grow_field!(s, _n, :idx_gens, Int64(typemax(UInt32)))
    nothing
end
