"""
Fixes the limitations of Gen at the cost of 4-8 times the memory footprint.
"""
mutable struct Dyn <: UniqueID
    ids::Memory{Int64}
    idx_slots::Memory{NTuple{2, Int64}}
    n_active::Int64
    next_id::Int64
    mask::Int64
end

function Dyn()
    idx_slots = Memory{NTuple{2, Int64}}(undef, 1)
    idx_slots[1] = (Int64(0), Int64(0))
    Dyn(
        Memory{Int64}(undef,0),
        idx_slots,
        Int64(0),
        Int64(1),
        Int64(0),
    )
end

function reset!(s::Dyn)::Dyn
    idx_slots = Memory{NTuple{2, Int64}}(undef, 1)
    idx_slots[1] = (Int64(0), Int64(0))
    s.ids = Memory{Int64}(undef,0)
    s.idx_slots = idx_slots
    s.n_active = Int64(0)
    s.next_id = Int64(1)
    s.mask = Int64(0)
    s
end

function Base.copy(s::Dyn)
    Dyn(
        copy(s.ids),
        copy(s.idx_slots),
        s.n_active,
        s.next_id,
        s.mask,
    )
end

function _assert_invariants_id2idx!(s::Dyn)
    @assert s.n_active ≤ length(s.idx_slots)
    @assert s.n_active == count(!iszero ∘ last, s.idx_slots)
    @assert length(s.idx_slots) - 1 == s.mask
    @assert ispow2(length(s.idx_slots))
    for (sidx, (idx, slot)) in enumerate(s.idx_slots)
        if !iszero(slot)
            @assert slot & s.mask == sidx - 1
        end
    end
    @assert !iszero(s.next_id)
    @assert iszero(last(s.idx_slots[begin + (s.next_id & s.mask)]))
    nothing
end

function next_id(s::Dyn)::Int64
    s.next_id
end

function _grow_idx_slots(s::Dyn, n::Int64)
    if n ≤ length(s.idx_slots) ÷ 2
        return
    else
        idx_slots = s.idx_slots
        mask = s.mask
        new_len = nextpow(2, n)*2
        @assert ispow2(new_len)
        new_mask = Int64(new_len) - 1
        new_idx_slots = Memory{NTuple{2, Int64}}(undef, new_len)
        fill!(new_idx_slots, (Int64(0), Int64(0)))
        # now copy in the ids
        for (sidx, (idx, slot)) in enumerate(idx_slots)
            if !iszero(slot)
                @assert slot & mask == sidx - 1
                new_idx_slots[begin + (slot & new_mask)] = (idx, slot)
            end
        end
        s.idx_slots = new_idx_slots
        s.mask = new_mask
        return
    end
end

function alloc_id!(s::Dyn)::Int64
    idx = s.n_active + 1
    _grow_field!(s, Int64(idx), :ids)
    # If free slots drops below 50% expand slots
    _grow_idx_slots(s, idx)
    id = s.next_id
    @inbounds s.idx_slots[begin + (id & s.mask)] = (idx, id)
    next_id = id
    @inbounds while true
        next_id += Int64(1)
        # Skip zero so it can be used as a null
        if iszero(next_id)
            next_id = Int64(1)
        end
        if iszero(last(s.idx_slots[begin + (next_id & s.mask)]))
            break
        end
    end
    s.next_id = next_id
    s.n_active += Int64(1)
    @inbounds s.ids[idx] = id
    id
end

function _pop_id2idx!(s::Dyn, id::Int64)::Int
    if id ∉ s
        throw(KeyError(id))
    end
    @inbounds idx = first(s.idx_slots[begin + (id & s.mask)])
    @inbounds s.idx_slots[begin + (id & s.mask)] = (Int64(0), Int64(0))
    s.n_active -= Int64(1)
    idx
end

Base.@propagate_inbounds function _set_id2idx!(s::Dyn, idx::Int, id::Int64)::Nothing
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    @inbounds s.idx_slots[begin + (id & s.mask)] = (idx, id)
    nothing
end

function Base.size(s::Dyn)
    (Int(s.n_active),)
end

function Base.in(id::Int64, s::Dyn)::Bool
    if iszero(id)
        return false
    end
    @inbounds return last(s.idx_slots[begin + (id & s.mask)]) == id
end

Base.@propagate_inbounds function id2idx(s::Dyn, id::Int64)::Int
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    @inbounds first(s.idx_slots[begin + (id & s.mask)])
end

function Base.empty!(s::Dyn)::Dyn
    fill!(s.idx_slots, (Int64(0), Int64(0)))
    s.n_active = UInt32(0)
    s
end

function _sizehint_id2idx!(s::Dyn, n; kwargs...)
    _grow_idx_slots(s, clamp(n, Int64))
    nothing
end
