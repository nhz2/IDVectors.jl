"""
The next id is just 1 + the last id
The id will wrap around to negative values, but avoid zero.
"""
mutable struct Inc <: UniqueID
    ids::Memory{Int64}
    const id2idx::Dict{Int64, Int}
    next_id::Int64
end

function Inc()
    Inc(Memory{Int64}(undef,0), Dict{Int64, Int}(), Int64(1))
end

function reset!(s::Inc)::Inc
    s.next_id = Int64(1)
    empty!(s.id2idx)
    sizehint!(s.id2idx, 0)
    s.ids = Memory{Int64}(undef, 0)
    s
end

function Base.copy(s::Inc)
    Inc(copy(s.ids), copy(s.id2idx), s.next_id)
end

function _assert_invariants_id2idx!(s::Inc)
    nothing
end

function next_id(s::Inc)::Int64
    s.next_id
end

function alloc_id!(s::Inc)::Int64
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

function _pop_id2idx!(s::Inc, id::Int64)::Int
    pop!(s.id2idx, id)
end

function _set_id2idx!(s::Inc, idx::Int, id::Int64)::Nothing
    s.id2idx[id] = idx
    nothing
end

function Base.size(s::Inc)
    (length(s.id2idx),)
end

function Base.in(id::Int64, s::Inc)::Bool
    haskey(s.id2idx, id)
end

function id2idx(s::Inc, id::Int64)::Int
    s.id2idx[id]
end

function Base.empty!(s::Inc)
    empty!(s.id2idx)
    s
end

function _sizehint_id2idx!(s::Inc, n; kwargs...)
    sizehint!(s.id2idx, n; kwargs...)
    nothing
end
