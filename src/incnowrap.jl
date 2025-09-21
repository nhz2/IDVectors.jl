"""
The next id is just 1 + the last id
The id go up to 2^64 then error if more ids are allocated.
"""
mutable struct IncNoWrapIDSet <: IDSet
    const used_ids::Set{Int64}
    next_id::Int64
end

function IncNoWrapIDSet()
    IncNoWrapIDSet(Set{Int64}(), Int64(1))
end

function assert_invariants(s::IncNoWrapIDSet)
    @assert s.next_id ∉ s.used_ids
    @assert Int64(0) ∉ s.used_ids
    nothing
end

function next_id(s::IncNoWrapIDSet)::Int64
    iszero(s.next_id) && throw(OverflowError("next_id would wraparound"))
    s.next_id
end

function alloc_id!(s::IncNoWrapIDSet)::Int64
    iszero(s.next_id) && throw(OverflowError("next_id would wraparound"))
    id = s.next_id
    push!(s.used_ids, id)
    s.next_id = id + Int64(1)
    id
end

function free_id!(s::IncNoWrapIDSet, id::Int64)::IncNoWrapIDSet
    if id ∉ s
        throw(KeyError(id))
    else
        pop!(s.used_ids, id)
    end
    s
end

function reset!(s::IncNoWrapIDSet)::IncNoWrapIDSet
    s.next_id = Int64(1)
    empty!(s.used_ids)
    sizehint!(s.used_ids, 0; shrink=true)
    s
end

# Functions from Base

function Base.in(id::Int64, s::IncNoWrapIDSet)::Bool
    id ∈ s.used_ids
end

Base.length(s::IncNoWrapIDSet) = length(s.used_ids)
Base.iterate(s::IncNoWrapIDSet, state) = iterate(s.used_ids, state)
Base.iterate(s::IncNoWrapIDSet) = iterate(s.used_ids)
Base.isdone(s::IncNoWrapIDSet) = Base.isdone(s.used_ids)
Base.isdone(s::IncNoWrapIDSet, state) = Base.isdone(s.used_ids, state)

function Base.empty!(s::IncNoWrapIDSet)::IncNoWrapIDSet
    empty!(s.used_ids)
    s
end

function Base.sizehint!(s::IncNoWrapIDSet, n; kwargs...)::IncNoWrapIDSet
    sizehint!(s.used_ids, n; kwargs...)
    s
end
