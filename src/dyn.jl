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

function free_id!(s::DynIDSet, id::Int64)::DynIDSet
    if id ∉ s
        throw(KeyError(id))
    end
    s.slots[begin + (id & s.mask)] = Int64(0)
    s.n_active -= Int64(1)
    s
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
