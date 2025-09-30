module IDVectors

export next_id,
    alloc_id!,
    free_id!,
    id2idx,
    swap_deleteat!,
    swap!,
    IncIDSet,
    GenIDSet,
    GenNoWrapIDSet,
    DynIDSet,
    IncIDVector,
    GenIDVector,
    GenNoWrapIDVector,
    DynIDVector

public reset!,
    assert_invariants

"""
    abstract type IDSet end

Used to allocate ids. ids are never zero.
Subtypes should implement:
- `next_id(s::IDSet)::Int64`
- `alloc_id!(s::IDSet)::Int64`
- `free_id!(s::IDSet, id::Int64) -> s`
- `reset!(s::IDSet) -> s`
- `assert_invariants(s::IDSet)::Nothing`
- `Base.in(id::Int64, s::IDSet)::Bool`
- `Base.length`
- `Base.iterate`
- `Base.empty!`
- `Base.sizehint!`
"""
abstract type IDSet end

Base.eltype(::Type{<:IDSet}) = Int64

"""
    next_id(s::Union{IDSet, IDVector})::Int64

Return the next id that would be allocated if `alloc_id!`
was called instead. This id is not in `s`, though due to
wrap around it may have been allocated and freed in the past.
"""
function next_id end

"""
    alloc_id!(s::Union{IDSet, IDVector})::Int64

Return the allocated id, this key is guaranteed to not
"""
function alloc_id! end

"""
    free_id!(s::IDSet, id::Int64) -> nothing
    free_id!(s::IDVector, id::Int64) -> idx

Remove `id` from `s` and return its previous index if `s isa IDVector`.
Throw a `KeyError` if `id` isn't in `s`.
"""
function free_id! end

"""
    reset!(s::Union{IDSet, IDVector}) -> s

Reset `s`, emptying it and also removing memory of past allocated ids.
"""
function reset! end

"""
    assert_invariants(s::Union{IDSet, IDVector})::Nothing

Assert that `s` is in a valid state.
Useful for testing or hacking at the data structure.
"""
function assert_invariants end


"""
    abstract type IDVector <: AbstractVector{Int64} end

A vector of unique ids with accelerated mapping from id to index.
"""
abstract type IDVector <: AbstractVector{Int64} end

function free_id!(s::IDVector, id::Int64)
    if id ∉ s
        throw(KeyError(id))
    else
        ids_len = length(s)
        idx = _pop_id2idx!(s, id)
        if idx != ids_len
            # swap remove from ids, and update id2idx
            idend = s.ids[ids_len]
            s.ids[idx] = idend
            _set_id2idx!(s, idx, idend)
        end
        idx
    end
end

function Base.pop!(s::IDVector)
    id = last(s)
    _pop_id2idx!(s, id)
    id
end
function Base.popfirst!(s::IDVector)
    popat!(s, 1)
end
function Base.popat!(s::IDVector, idx::Integer)
    id = s[idx]
    ids_len = length(s)
    _pop_id2idx!(s, id)
    # do the inplace shift
    if idx != ids_len
        unsafe_copyto!(s.ids, idx, s.ids, idx + 1, ids_len-idx)
        for i in idx + 1 : ids_len
            _set_id2idx!(s, i-1, s.ids[i-1])
        end
    end
    id
end
function Base.popat!(s::IDVector, idx::Integer, default)
    if idx ∈ eachindex(s)
        id = s[idx]
        ids_len = length(s)
        _pop_id2idx!(s, id)
        # do the inplace shift
        if idx != ids_len
            unsafe_copyto!(s.ids, idx, s.ids, idx + 1, ids_len-idx)
            for i in idx + 1 : ids_len
                _set_id2idx!(s, i-1, s.ids[i-1])
            end
        end
        id
    else
        default
    end
end
function Base.deleteat!(s::IDVector, idx::Integer)
    popat!(s, idx)
    s
end
function Base.deleteat!(a::IDVector, inds::AbstractVector{Bool})
    n = length(a)
    length(inds) == n || throw(BoundsError(a, inds))
    p = 1
    for (q, i) in enumerate(inds)
        if !i
            swap!(a, p, q)
            p += 1
        end
    end
    n_delete = n - p + 1
    for i in 1:n_delete
        pop!(a)
    end
    a
end
function Base.deleteat!(a::IDVector, inds)
    n_delete = 0
    lastidx::Int = -1
    p = 1
    q = 1
    for _i in inds
        n_delete += 1
        # inds must be sorted and unique
        idx = Int(_i)::Int
        if idx ≤ lastidx
            throw(ArgumentError("indices must be unique and sorted"))
        end
        while q != idx
            swap!(a, p, q)
            p += 1
            q += 1
        end
        q += 1
        lastidx = idx
    end
    while q ≤ length(a)
        swap!(a, p, q)
        p += 1
        q += 1
    end
    for i in 1 : n_delete
        pop!(a)
    end
    a
end
function Base.keepat!(a::IDVector, inds::AbstractVector{Bool})
    n = length(a)
    length(inds) == n || throw(BoundsError(a, inds))
    p = 1
    for (q, i) in enumerate(inds)
        if i
            swap!(a, p, q)
            p += 1
        end
    end
    n_delete = n - p + 1
    for i in 1:n_delete
        pop!(a)
    end
    a
end
function Base.keepat!(a::IDVector, inds)
    n_keep = 0
    n = length(a)
    lastidx::Int = -1
    p = 1
    for _i in inds
        n_keep += 1
        # inds must be sorted and unique
        idx = Int(_i)::Int
        if idx ≤ lastidx
            throw(ArgumentError("indices must be unique and sorted"))
        end
        swap!(a, p, idx)
        p += 1
        lastidx = idx
    end
    n_delete = n - n_keep
    for i in 1:n_delete
        pop!(a)
    end
    a
end
function Base.filter!(f, a::IDVector)
    keep = Bool[f(id) for id in a]
    keepat!(a, keep)
    a
end
function swap_deleteat!(s::AbstractVector, idx::Int)
    swap!(s, idx, lastindex(s))
    pop!(s)
    s
end
function swap_deleteat!(a::AbstractVector, inds::AbstractVector{Bool})
    n = length(a)
    length(inds) == n || throw(BoundsError(a, inds))
    start = 1
    stop = n
    while start ≤ stop
        if inds[begin + stop - 1]
            pop!(a)
            stop -= 1
        elseif inds[begin + start - 1]
            swap!(a, start, stop)
            pop!(a)
            start += 1
            stop -= 1
        else
            start += 1
        end
    end
    a
end
function swap_deleteat!(a::AbstractVector, inds::Union{AbstractVector, Tuple})
    start = 1
    stop = Int(length(inds))::Int
    lastidx = -1
    while start ≤ stop
        # inds must be sorted and unique
        idxstop = Int(inds[begin + stop - 1])::Int
        idxstart = Int(inds[begin + start - 1])::Int
        if idxstart ≤ lastidx || idxstop > length(a)
            throw(ArgumentError("indices must be unique and sorted"))
        end
        if idxstop == length(a)
            pop!(a)
            stop -= 1
        else
            swap!(a, idxstart, length(a))
            pop!(a)
            start += 1
            lastidx = idxstart
        end
    end
    a
end

# Swap from UniqueVectors.jl

"""
    swap!(s::AbstractVector, a::Int, b::Int) -> s

Swap the positions of ids at index a and b
"""
Base.@propagate_inbounds function swap!(s::IDVector, a::Int, b::Int)
    @boundscheck checkbounds(s, a)
    @boundscheck checkbounds(s, b)
    if a != b
        ida = s.ids[a]
        idb = s.ids[b]
        _set_id2idx!(s, a, idb)
        _set_id2idx!(s, b, ida)
        s.ids[b] = ida
        s.ids[a] = idb
    end
    s
end
Base.@propagate_inbounds function swap!(s::AbstractVector, a::Int, b::Int)
    @boundscheck checkbounds(s, a)
    @boundscheck checkbounds(s, b)
    if a != b
        va = s[a]
        vb = s[b]
        s[a] = vb
        s[b] = va
    end
    s
end

function Base.permute!(s::IDVector, perm::AbstractVector)
    old_ids = s.ids
    new_ids = similar(s.ids)
    for (a, b) in enumerate(perm)
        _set_id2idx!(s, a, old_ids[b])
        new_ids[a] = old_ids[b]
    end
    s.ids = new_ids
    s
end
function Base.invpermute!(s::IDVector, perm::AbstractVector)
    old_ids = s.ids
    new_ids = similar(s.ids)
    for (a, b) in enumerate(perm)
        _set_id2idx!(s, b, old_ids[a])
        new_ids[b] = old_ids[a]
    end
    s.ids = new_ids
    s
end

function assert_invariants(s::IDVector)
    @assert !iszero(next_id(s))
    @assert next_id(s) ∉ s
    @assert Int64(0) ∉ s
    for idx in 1:length(s)
        id = s.ids[idx]
        @assert findfirst(isequal(id), s) == idx
        @assert id ∈ s
    end
    _assert_invariants_id2idx!(s)
    nothing
end

@inline function Base.getindex(s::IDVector, idx::Int)
    @boundscheck checkbounds(s, idx)
    getindex(s.ids, idx)
end

function Base.findfirst(p::Base.Fix2{typeof(isequal), Int64}, s::IDVector)
    if p.x ∈ s
        id2idx(s, p.x)
    else
        nothing
    end
end
function Base.findlast(p::Base.Fix2{typeof(isequal), Int64}, s::IDVector)
    if p.x ∈ s
        id2idx(s, p.x)
    else
        nothing
    end
end
function Base.indexin(a, s::IDVector)
    Union{Nothing, Int}[findfirst(isequal(id), s) for id in a]
end
function Base.findnext(p::Base.Fix2{typeof(isequal), Int64}, s::IDVector, i::Integer)
    if p.x ∈ s
        idx = id2idx(s, p.x)
        if idx < i
            nothing
        else
            idx
        end
    else
        nothing
    end
end
function Base.findprev(p::Base.Fix2{typeof(isequal), Int64}, s::IDVector, i::Integer)
    if p.x ∈ s
        idx = id2idx(s, p.x)
        if idx > i
            nothing
        else
            idx
        end
    else
        nothing
    end
end
function Base.findall(p::Base.Fix2{typeof(isequal), Int64}, s::IDVector)
    if p.x ∈ s
        Int[id2idx(s, p.x)]
    else
        Int[]
    end
end

function Base.count(p::Base.Fix2{typeof(isequal), Int64}, s::IDVector)
    Int(p.x ∈ s)
end

function Base.sizehint!(s::IDVector, n; kwargs...)
    newsize = max(Int(n), length(s))
    _sizehint_id2idx!(s, newsize; kwargs...)
    if newsize != length(s.ids)
        new_ids = Memory{Int64}(undef, newsize)
        unsafe_copyto!(new_ids, 1, s.ids, 1, length(s))
        s.ids = new_ids
    end
    s
end

function Base.allunique(::IDVector)
    true
end

function Base.unique(s::IDVector)
    copy(s)
end
function Base.unique!(s::IDVector)
    s
end

include("utils.jl")
include("inc.jl")
include("gen.jl")
include("gennowrap.jl")
include("dyn.jl")

end
