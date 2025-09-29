# Keep the free_queue with this many entries to avoid the
# generation wrapping around too often
const MIN_FREE_QUEUE_LEN = 2^16-1

"""
The 32 most significant bits of an id is the generation. Even generations are active, odd generations are inactive.
The 32 least significant bits of an id is an index.
id's are never zero.
IDs may wrap around after about 2^47 pairs of alloc and free.
"""
mutable struct GenIDSet <: IDSet
    gens::Memory{UInt32}
    gens_len::UInt32
    n_active::UInt32
    free_queue::Memory{UInt32}
    free_read_head::UInt32
    free_write_head::UInt32
end

function GenIDSet()
    GenIDSet(
        Memory{UInt32}(undef, 0),
        UInt32(0),
        UInt32(0),
        Memory{UInt32}(undef, 0),
        UInt32(0),
        UInt32(0),
    )
end

function reset!(s::GenIDSet)::GenIDSet
    s.gens = Memory{UInt32}(undef, 0)
    s.gens_len = UInt32(0)
    s.n_active = UInt32(0)
    s.free_queue = Memory{UInt32}(undef, 0)
    s.free_read_head = UInt32(0)
    s.free_write_head = UInt32(0)
    s
end

function Base.copy(s::GenIDSet)
    GenIDSet(copy(s.gens), s.gens_len, s.n_active, copy(s.free_queue), s.free_read_head, s.free_write_head)
end

function assert_invariants(s::GenIDSet)
    @assert s.n_active ≤ s.gens_len
    n_inactive = count(isodd, view(s.gens, 1:min(s.gens_len, length(s.gens))))
    @assert n_inactive == s.gens_len - s.n_active
    # The free queue should always have at least one free spot unless it's not allocated yet
    @assert length(s.free_queue) == 0 || length(s.free_queue) > n_inactive
    @assert length(s.gens) ≤ typemax(UInt32)
    for i in s.gens_len+1:length(s.gens)
        @assert iszero(s.gens[i])
    end
    if iszero(n_inactive)
        @assert s.free_read_head == s.free_write_head
    else
        @assert s.free_read_head + 1 ∈ eachindex(s.free_queue)
        @assert s.free_write_head + 1 ∈ eachindex(s.free_queue)
        i = s.free_read_head
        free_write_head = s.free_write_head
        n = 0
        free_set = Set{UInt32}()
        while i != free_write_head
            n += 1
            f = s.free_queue[1 + i]
            @assert isodd(s.gens[f])
            push!(free_set, f)
            i += UInt32(1)
            if i ≥ length(s.free_queue)
                i = UInt32(0)
            end
        end
        @assert n == n_inactive
        @assert length(free_set) == n
    end
    nothing
end

function next_id(s::GenIDSet)::Int64
    n_active = s.n_active
    gens_len = s.gens_len
    if gens_len - n_active ≤ MIN_FREE_QUEUE_LEN
        # No free slots make a new one with implicit generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        Int64(gens_len + UInt32(1))
    else
        # Pick a slot off the free queue
        f = s.free_queue[1 + s.free_read_head]
        new_gen = s.gens[f] + UInt32(1)
        Int64(new_gen)<<32 | Int64(f)
    end
end

function alloc_id!(s::GenIDSet)::Int64
    n_active = s.n_active
    gens_len = s.gens_len
    if gens_len - n_active ≤ MIN_FREE_QUEUE_LEN
        # No free slots make a new one with implicit generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        s.gens_len += UInt32(1)
        s.n_active += UInt32(1)
        Int64(s.gens_len)
    else
        # Pick a slot off the free queue
        i = s.free_read_head
        f = s.free_queue[1 + i]
        i += UInt32(1)
        if i ≥ length(s.free_queue)
            i = UInt32(0)
        end
        s.free_read_head = i
        new_gen = s.gens[f] + UInt32(1)
        s.gens[f] = new_gen
        s.n_active += UInt32(1)
        Int64(new_gen)<<32 | Int64(f)
    end
end

# Expand the size of s.gens to at least n
function _grow_gens!(s::GenIDSet, n::Int64)
    _grow_fill_field!(s, n, UInt32(0), :gens, Int64(typemax(UInt32)))
end

# Expand the size of s.free_queue to be able to store at least n free slots
function _grow_free_queue!(s, n::Int64)
    old_free_queue = s.free_queue
    old_queue_size = length(old_free_queue)
    if n < old_queue_size
        return
    end
    rh = s.free_read_head
    wh = s.free_write_head
    @assert n ∈ old_queue_size : Int64(typemax(UInt32))
    new_queue_size = Int(min(overallocation(n+1), Int64(2)^32))
    new_free_queue = fill!(Memory{UInt32}(undef, new_queue_size), UInt32(0))
    if wh == rh
        # queue is empty
        s.free_write_head = UInt32(0)
    elseif wh > rh
        unsafe_copyto!(new_free_queue, 1, old_free_queue, Int(rh)+1, Int(wh-rh))
        s.free_write_head = wh-rh
    else
        nr_data = old_queue_size%UInt32 - rh
        unsafe_copyto!(new_free_queue, 1, old_free_queue, Int(rh)+1, Int(nr_data))
        unsafe_copyto!(new_free_queue, Int(nr_data)+1, old_free_queue, 1, wh)
        s.free_write_head = nr_data + wh
    end
    s.free_queue = new_free_queue
    s.free_read_head = UInt32(0)
    return
end

function free_id!(s::GenIDSet, id::Int64)::Nothing
    if id ∉ s
        throw(KeyError(id))
    end
    idx = id%UInt32
    gen = (id>>>32)%UInt32
    # Do the memory allocations first to avoid corrupting s in case that errors
    _grow_gens!(s, Int64(idx))
    n_inactive = s.gens_len - s.n_active
    _grow_free_queue!(s, max(n_inactive + Int64(1), MIN_FREE_QUEUE_LEN))
    # We made it past the scary allocation parts!
    # next push idx to the free queue
    i = s.free_write_head
    s.free_queue[1 + i] = idx
    i += UInt32(1)
    if i ≥ length(s.free_queue)
        i = UInt32(0)
    end
    s.free_write_head = i
    # finally update gens
    @assert s.gens[idx] == gen
    @assert iseven(gen)
    s.gens[idx] = gen + UInt32(1)
    @assert !iszero(s.n_active)
    s.n_active -= UInt32(1)
    nothing
end

# Functions from Base

function Base.in(id::Int64, s::GenIDSet)::Bool
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
    saved_gen = if idx ≤ length(s.gens)
        s.gens[idx]
    else
        UInt32(0)
    end
    if saved_gen != gen
        return false
    end
    return true
end

Base.length(s::GenIDSet) = Int(s.n_active)
function Base.iterate(s::GenIDSet, state::NamedTuple)
    gens = s.gens
    nextidx = state.curidx
    while true
        nextidx += 1
        if nextidx > s.gens_len
            return nothing
        elseif nextidx > length(gens)
            return (nextidx, (; curidx=nextidx))
        else
            gen = gens[nextidx]
            if iseven(gen)
                return (Int64(gen)<<32 | nextidx, (; curidx=nextidx))
            end
        end
    end
end
Base.iterate(s::GenIDSet) = iterate(s, (; curidx=Int64(0)))

function Base.empty!(s::GenIDSet)::GenIDSet
    n = s.gens_len
    _grow_gens!(s, Int64(n))
    _grow_free_queue!(s, Int64(n))
    for idx in UInt32(1):n
        gen = s.gens[idx]
        if iseven(gen)
            i = s.free_write_head
            s.free_queue[1 + i] = idx
            i += UInt32(1)
            if i ≥ length(s.free_queue)
                i = UInt32(0)
            end
            s.free_write_head = i
            s.gens[idx] = gen + UInt32(1)
        end
    end
    s.n_active = UInt32(0)
    s
end

function Base.sizehint!(s::GenIDSet, n; kwargs...)::GenIDSet
    _n = clamp(n, 0, Int64(typemax(UInt32)) - MIN_FREE_QUEUE_LEN)%Int64
    _n = _n + MIN_FREE_QUEUE_LEN
    _grow_gens!(s, _n)
    _grow_free_queue!(s, _n)
    s
end

"""
The 32 most significant bits of an id is the generation. Even generations are active, odd generations are inactive.
The 32 least significant bits of an id is an index.
id's are never zero.
IDs may wrap around after about 2^47 pairs of alloc and free.
"""
mutable struct GenIDVector <: IDVector
    ids::Memory{Int64}
    idx_gens::Memory{NTuple{2, UInt32}}
    gens_len::UInt32
    n_active::UInt32
    free_queue::Memory{UInt32}
    free_read_head::UInt32
    free_write_head::UInt32
end

function GenIDVector()
    GenIDVector(
        Memory{Int64}(undef,0),
        Memory{NTuple{2, UInt32}}(undef, 0),
        UInt32(0),
        UInt32(0),
        Memory{UInt32}(undef, 0),
        UInt32(0),
        UInt32(0),
    )
end

function reset!(s::GenIDVector)::GenIDVector
    s.ids = Memory{Int64}(undef,0)
    s.idx_gens = Memory{NTuple{2, UInt32}}(undef, 0)
    s.gens_len = UInt32(0)
    s.n_active = UInt32(0)
    s.free_queue = Memory{UInt32}(undef, 0)
    s.free_read_head = UInt32(0)
    s.free_write_head = UInt32(0)
    s
end

function Base.copy(s::GenIDVector)
    GenIDVector(
        copy(s.ids),
        copy(s.idx_gens),
        s.gens_len,
        s.n_active,
        copy(s.free_queue),
        s.free_read_head,
        s.free_write_head,
    )
end

function _assert_invariants_id2idx!(s::GenIDVector)
    @assert s.gens_len ≤ length(s.idx_gens)
    @assert s.n_active ≤ s.gens_len
    n_inactive = count(isodd ∘ last, view(s.idx_gens, 1:s.gens_len))
    @assert n_inactive == s.gens_len - s.n_active
    # The free queue should always have at least one free spot unless it's not allocated yet
    @assert length(s.free_queue) == 0 || length(s.free_queue) > n_inactive
    @assert length(s.idx_gens) ≤ typemax(UInt32)
    if iszero(n_inactive)
        @assert s.free_read_head == s.free_write_head
    else
        @assert s.free_read_head + 1 ∈ eachindex(s.free_queue)
        @assert s.free_write_head + 1 ∈ eachindex(s.free_queue)
        i = s.free_read_head
        free_write_head = s.free_write_head
        n = 0
        free_set = Set{UInt32}()
        while i != free_write_head
            n += 1
            f = s.free_queue[1 + i]
            @assert isodd(last(s.idx_gens[f]))
            push!(free_set, f)
            i += UInt32(1)
            if i ≥ length(s.free_queue)
                i = UInt32(0)
            end
        end
        @assert n == n_inactive
        @assert length(free_set) == n
    end
    nothing
end

function next_id(s::GenIDVector)::Int64
    n_active = s.n_active
    gens_len = s.gens_len
    if gens_len - n_active ≤ MIN_FREE_QUEUE_LEN
        # No free slots make a new one with implicit generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        Int64(gens_len + UInt32(1))
    else
        # Pick a slot off the free queue
        f = s.free_queue[1 + s.free_read_head]
        new_gen = last(s.idx_gens[f]) + UInt32(1)
        Int64(new_gen)<<32 | Int64(f)
    end
end

function alloc_id!(s::GenIDVector)::Int64
    n_active = s.n_active
    if n_active == typemax(UInt32)
        throw(OverflowError("next_id would wraparound"))
    end
    idx = n_active + UInt32(1)
    _grow_field!(s, Int64(idx), :ids)
    gens_len = s.gens_len
    id = if gens_len - n_active ≤ MIN_FREE_QUEUE_LEN
        # No free slots make a new one with generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        _grow_field!(s, Int64(gens_len + UInt32(1)), :idx_gens, Int64(typemax(UInt32)))
        s.gens_len += UInt32(1)
        s.idx_gens[s.gens_len] = (idx, UInt32(0))
        s.n_active += UInt32(1)
        Int64(s.gens_len)
    else
        # Pick a slot off the free queue
        i = s.free_read_head
        f = s.free_queue[1 + i]
        i += UInt32(1)
        if i ≥ length(s.free_queue)
            i = UInt32(0)
        end
        s.free_read_head = i
        new_gen = last(s.idx_gens[f]) + UInt32(1)
        s.idx_gens[f] = (idx, new_gen)
        s.n_active += UInt32(1)
        Int64(new_gen)<<32 | Int64(f)
    end
    s.ids[idx] = id
    id
end

function _pop_id2idx!(s::GenIDVector, id::Int64)::Int
    if id ∉ s
        throw(KeyError(id))
    end
    gidx = id%UInt32
    gen = (id>>>32)%UInt32
    idx, storedgen = s.idx_gens[gidx]
    # Do the memory allocations first to avoid corrupting s in case that errors
    n_inactive = s.gens_len - s.n_active
    _grow_free_queue!(s, max(n_inactive + Int64(1), MIN_FREE_QUEUE_LEN))
    # We made it past the scary allocation parts!
    # next push gidx to the free queue
    i = s.free_write_head
    s.free_queue[1 + i] = gidx
    i += UInt32(1)
    if i ≥ length(s.free_queue)
        i = UInt32(0)
    end
    s.free_write_head = i
    # finally update gens
    s.idx_gens[gidx] = (UInt32(0), gen + UInt32(1))
    @assert !iszero(s.n_active)
    s.n_active -= UInt32(1)
    idx
end

Base.@propagate_inbounds function _set_id2idx!(s::GenIDVector, idx::Int, id::Int64)::Nothing
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    gidx = id%UInt32
    gen = (id>>>32)%UInt32
    s.idx_gens[gidx] = (idx, gen)
    nothing
end


function Base.size(s::GenIDVector)
    (Int(s.n_active),)
end

function Base.in(id::Int64, s::GenIDVector)::Bool
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
    saved_gen = last(s.idx_gens[idx])
    if saved_gen != gen
        return false
    end
    return true
end

Base.@propagate_inbounds function id2idx(s::GenIDVector, id::Int64)::Int
    @boundscheck if id ∉ s
        throw(KeyError(id))
    end
    idx = id%UInt32
    first(s.idx_gens[idx])
end

function Base.empty!(s::GenIDVector)::GenIDVector
    n = s.gens_len
    _grow_free_queue!(s, Int64(n))
    for gidx in UInt32(1):n
        idx, gen = s.idx_gens[gidx]
        if iseven(gen)
            i = s.free_write_head
            s.free_queue[1 + i] = idx
            i += UInt32(1)
            if i ≥ length(s.free_queue)
                i = UInt32(0)
            end
            s.free_write_head = i
            s.idx_gens[idx] = (UInt32(0), gen + UInt32(1))
        end
    end
    s.n_active = UInt32(0)
    s
end

function _sizehint_id2idx!(s::GenIDVector, n; kwargs...)
    _n = clamp(n, 0, Int64(typemax(UInt32)) - MIN_FREE_QUEUE_LEN)%Int64
    _n = _n + MIN_FREE_QUEUE_LEN
    _grow_field!(s, _n, :idx_gens, Int64(typemax(UInt32)))
    _grow_free_queue!(s, _n)
    nothing
end
