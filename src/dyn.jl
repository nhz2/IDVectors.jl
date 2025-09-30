"""

"""
mutable struct DynIDSet <: IDSet
    slots::Memory{Int64}
    n_active::Int64
    next_id::Int64
    mask::Int64
end

function DynIDSet()
    slots = Memory{Int64}(undef, 1)
    slots[1] = 0
    DynIDSet(
        slots,
        Int64(0),
        Int64(1),
        Int64(0),
    )
end

function reset!(s::DynIDSet)::DynIDSet
    slots = Memory{Int64}(undef, 1)
    slots[1] = 0
    s.slots = slots
    s.n_active = Int64(0)
    s.next_id = Int64(1)
    s.mask = Int64(0)
    s
end

function Base.copy(s::DynIDSet)
    DynIDSet(
        copy(s.slots),
        s.n_active,
        s.next_id,
        s.mask,
    )
end

function assert_invariants(s::DynIDSet)
    @assert s.n_active ≤ length(s.slots)
    @assert s.n_active == count(!iszero, s.slots)
    @assert length(s.slots) - 1 == s.mask
    @assert ispow2(length(s.slots))
    for (idx, slot) in enumerate(s.slots)
        if !iszero(slot)
            @assert slot & s.mask == idx - 1
        end
    end
    @assert !iszero(s.next_id)
    @assert iszero(s.slots[begin + (s.next_id & s.mask)])
    nothing
end

function next_id(s::DynIDSet)::Int64
    s.next_id
end

function _grow_slots(s::DynIDSet, n::Int64)
    if n ≤ length(s.slots) ÷ 2
        return
    else
        slots = s.slots
        mask = s.mask
        new_len = nextpow(2, n)*2
        @assert ispow2(new_len)
        new_mask = Int64(new_len) - 1
        new_slots = Memory{Int64}(undef, new_len)
        fill!(new_slots, Int64(0))
        # now copy in the ids
        for (idx, slot) in enumerate(slots)
            if !iszero(slot)
                @assert slot & mask == idx - 1
                new_slots[begin + (slot & new_mask)] = slot
            end
        end
        s.slots = new_slots
        s.mask = new_mask
        return
    end
end

function alloc_id!(s::DynIDSet)::Int64
    # If free slots drops below 50% expand slots
    _grow_slots(s, s.n_active + 1)
    id = s.next_id
    s.slots[begin + (id & s.mask)] = id
    next_id = id
    while true
        next_id += Int64(1)
        # Skip zero so it can be used as a null
        if iszero(next_id)
            next_id = Int64(1)
        end
        if iszero(s.slots[begin + (next_id & s.mask)])
            break
        end
    end
    s.next_id = next_id
    s.n_active += Int64(1)
    id
end

function free_id!(s::DynIDSet, id::Int64)::Nothing
    if id ∉ s
        throw(KeyError(id))
    end
    s.slots[begin + (id & s.mask)] = Int64(0)
    s.n_active -= Int64(1)
    nothing
end

# Functions from Base

function Base.in(id::Int64, s::DynIDSet)::Bool
    if iszero(id)
        return false
    end
    return s.slots[begin + (id & s.mask)] == id
end

Base.length(s::DynIDSet) = Int(s.n_active)
function Base.iterate(s::DynIDSet, state::NamedTuple)
    slots = s.slots
    nextidx = state.curidx
    while true
        nextidx += 1
        if nextidx > length(slots)
            return nothing
        else
            id = slots[nextidx]
            if !iszero(id)
                return (id, (; curidx=nextidx))
            end
        end
    end
end
Base.iterate(s::DynIDSet) = iterate(s, (; curidx=Int64(0)))

function Base.empty!(s::DynIDSet)::DynIDSet
    fill!(s.slots, Int64(0))
    s.n_active = Int64(0)
    s
end

function Base.sizehint!(s::DynIDSet, n; kwargs...)::DynIDSet
    _grow_slots(s, clamp(n, Int64))
    s
end


"""
Fixes the limitations of GenIDVector at the cost of 4-8 times the memory footprint.
"""
mutable struct DynIDVector <: IDVector
    ids::Memory{Int64}
    idx_slots::Memory{NTuple{2, Int64}}
    n_active::Int64
    next_id::Int64
    mask::Int64
end

function DynIDVector()
    idx_slots = Memory{NTuple{2, Int64}}(undef, 1)
    idx_slots[1] = (Int64(0), Int64(0))
    DynIDVector(
        Memory{Int64}(undef,0),
        idx_slots,
        Int64(0),
        Int64(1),
        Int64(0),
    )
end

function reset!(s::DynIDVector)::DynIDVector
    idx_slots = Memory{NTuple{2, Int64}}(undef, 1)
    idx_slots[1] = (Int64(0), Int64(0))
    s.ids = Memory{Int64}(undef,0)
    s.idx_slots = idx_slots
    s.n_active = Int64(0)
    s.next_id = Int64(1)
    s.mask = Int64(0)
    s
end

function Base.copy(s::DynIDVector)
    DynIDVector(
        copy(s.ids),
        copy(s.idx_slots),
        s.n_active,
        s.next_id,
        s.mask,
    )
end

function _assert_invariants_id2idx!(s::DynIDVector)
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

function next_id(s::DynIDVector)::Int64
    s.next_id
end

function _grow_idx_slots(s::DynIDVector, n::Int64)
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

function alloc_id!(s::DynIDVector)::Int64
    idx = s.n_active + 1
    _grow_field!(s, Int64(idx), :ids)
    # If free slots drops below 50% expand slots
    _grow_idx_slots(s, idx)
    id = s.next_id
    s.idx_slots[begin + (id & s.mask)] = (idx, id)
    next_id = id
    while true
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
    s.ids[idx] = id
    id
end

function _pop_id2idx!(s::DynIDVector, id::Int64)::Int
    if id ∉ s
        throw(KeyError(id))
    end
    idx = first(s.idx_slots[begin + (id & s.mask)])
    s.idx_slots[begin + (id & s.mask)] = (Int64(0), Int64(0))
    s.n_active -= Int64(1)
    idx
end

Base.@propagate_inbounds function _set_id2idx!(s::DynIDVector, idx::Int, id::Int64)::Nothing
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    s.idx_slots[begin + (id & s.mask)] = (idx, id)
    nothing
end

function Base.size(s::DynIDVector)
    (Int(s.n_active),)
end

function Base.in(id::Int64, s::DynIDVector)::Bool
    if iszero(id)
        return false
    end
    return last(s.idx_slots[begin + (id & s.mask)]) == id
end

Base.@propagate_inbounds function id2idx(s::DynIDVector, id::Int64)::Int
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    first(s.idx_slots[begin + (id & s.mask)])
end

function Base.empty!(s::DynIDVector)::DynIDVector
    fill!(s.idx_slots, (Int64(0), Int64(0)))
    s.n_active = UInt32(0)
    s
end

function _sizehint_id2idx!(s::DynIDVector, n; kwargs...)
    _grow_idx_slots(s, clamp(n, Int64))
    nothing
end
