module IDVectors

export next_id,
    alloc_id!,
    free_id!,
    IncIDSet

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
    next_id(s::IDSet)::Int64

Return the next id that would be allocated if `alloc_id!`
was called instead. This id is not in `s`, though due to
wrap around it may have been allocated and freed in the past.
"""
function next_id end

"""
    alloc_id!(s::IDSet)::Int64

Return the allocated id, this key is guaranteed to not
"""
function alloc_id! end

"""
    free_id!(s::IDSet, id::Int64) -> s

Remove `id` from `s` and return `s`.
Throw a `KeyError` if `id` isn't in `s`.
"""
function free_id! end

"""
    reset!(s::IDSet) -> s

Reset `s`, emptying it and also removing memory of past allocated ids.
"""
function reset! end

"""
    assert_invariants(s::IDSet)::Nothing

Assert that `s` is in a valid state.
Useful for testing or hacking at the data structure.
"""
function assert_invariants end

include("utils.jl")
include("inc.jl")
include("incnowrap.jl")
include("gen.jl")

end
