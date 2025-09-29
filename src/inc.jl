"""
The next id is just 1 + the last id
The id will wrap around to negative values, but avoid zero.
"""
mutable struct IncIDSet <: IDSet
    const used_ids::Set{Int64}
    next_id::Int64
end

function IncIDSet()
    IncIDSet(Set{Int64}(), Int64(1))
end

function reset!(s::IncIDSet)::IncIDSet
    s.next_id = Int64(1)
    empty!(s.used_ids)
    sizehint!(s.used_ids, 0)
    s
end

function Base.copy(s::IncIDSet)
    IncIDSet(copy(s.used_ids), s.next_id)
end

function assert_invariants(s::IncIDSet)
    @assert !iszero(s.next_id)
    @assert s.next_id ∉ s.used_ids
    @assert Int64(0) ∉ s.used_ids
    nothing
end

function next_id(s::IncIDSet)::Int64
    s.next_id
end

function alloc_id!(s::IncIDSet)::Int64
    id = s.next_id
    used_ids = s.used_ids
    push!(used_ids, id)
    next_id = id
    # This loop handles overflow
    while true
        next_id += Int64(1)
        # Skip zero so it can be used as a null
        if iszero(next_id)
            next_id = Int64(1)
        end
        if next_id ∉ used_ids
            break
        end
    end
    s.next_id = next_id
    id
end

function free_id!(s::IncIDSet, id::Int64)::IncIDSet
    if id ∉ s
        throw(KeyError(id))
    else
        pop!(s.used_ids, id)
    end
    s
end

# Functions from Base

function Base.in(id::Int64, s::IncIDSet)::Bool
    id ∈ s.used_ids
end

Base.length(s::IncIDSet) = length(s.used_ids)
Base.iterate(s::IncIDSet, state) = iterate(s.used_ids, state)
Base.iterate(s::IncIDSet) = iterate(s.used_ids)
Base.isdone(s::IncIDSet) = Base.isdone(s.used_ids)
Base.isdone(s::IncIDSet, state) = Base.isdone(s.used_ids, state)

function Base.empty!(s::IncIDSet)::IncIDSet
    empty!(s.used_ids)
    s
end

function Base.sizehint!(s::IncIDSet, n; kwargs...)::IncIDSet
    sizehint!(s.used_ids, n; kwargs...)
    s
end

"""
The next id is just 1 + the last id
The id will wrap around to negative values, but avoid zero.
"""
mutable struct IncIDVector <: IDVector
    ids::Memory{Int64}
    const id2idx::Dict{Int64, Int}
    next_id::Int64
end

function IncIDVector()
    IncIDVector(Memory{Int64}(undef,0), Dict{Int64, Int}(), Int64(1))
end

function reset!(s::IncIDVector)::IncIDVector
    s.next_id = Int64(1)
    empty!(s.id2idx)
    sizehint!(s.id2idx, 0)
    s.ids = Memory{Int64}(undef, 0)
    s
end

function Base.copy(s::IncIDVector)
    IncIDVector(copy(s.ids), copy(s.id2idx), s.next_id)
end

function _assert_invariants_id2idx!(s::IncIDVector)
    nothing
end

function next_id(s::IncIDVector)::Int64
    s.next_id
end

function alloc_id!(s::IncIDVector)::Int64
    idx = length(s) + 1
    _grow_field!(s, Int64(idx), :ids)
    id = s.next_id
    s.id2idx[id] = idx
    next_id = id
    # This loop handles overflow
    while true
        next_id += Int64(1)
        # Skip zero so it can be used as a null
        if iszero(next_id)
            next_id = Int64(1)
        end
        if !haskey(s.id2idx, next_id)
            break
        end
    end
    s.next_id = next_id
    s.ids[idx] = id
    id
end

function _pop_id2idx!(s::IncIDVector, id::Int64)::Int
    pop!(s.id2idx, id)
end

function _set_id2idx!(s::IncIDVector, idx::Int, id::Int64)::Nothing
    s.id2idx[id] = idx
    nothing
end

function Base.size(s::IncIDVector)
    (length(s.id2idx),)
end

function Base.in(id::Int64, s::IncIDVector)::Bool
    haskey(s.id2idx, id)
end

function id2idx(s::IncIDVector, id::Int64)::Int
    s.id2idx[id]
end

function Base.empty!(s::IncIDVector)
    empty!(s.id2idx)
    s
end

function _sizehint_id2idx!(s::IncIDVector, n; kwargs...)
    sizehint!(s.id2idx, n; kwargs...)
    nothing
end
