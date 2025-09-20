# Keep the free_queue with this many entries to avoid the
# generation wrapping around too often
const MIN_FREE_QUEUE_LEN = 2^16-1

"""
The 31 most significant bits of an id is the generation.
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

function assert_invariants(s::GenIDSet)
    @assert s.n_active ≤ s.gens_len
    n_inactive = count(isodd, view(s.gens, 1:min(s.gens_len, length(s.gens))))
    @assert n_inactive == s.gens_len - s.n_active
    @assert length(s.free_queue) > n_inactive
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
        gens_len += UInt32(1)
        s.gens_len = gens_len
        s.n_active = gens_len
        Int64(gens_len)
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

function free_id!(s::GenIDSet, id::Int64)::GenIDSet
    if id ∉ s
        throw(KeyError(id))
    end
    idx = id%UInt32
    gen = (id>>>32)%UInt32
    # Do the memory allocations first to avoid corrupting s incase that errors
    if idx > length(s.gens)
        @assert iszero(gen)
        # need to allocate space to store the gen
        new_size = Int(min(overallocation(Int64(idx)), Int64(typemax(UInt32))))
        old_gens = s.gens
        new_gens = fill!(Memory{UInt32}(undef, new_size), UInt32(0))
        unsafe_copyto!(new_gens, 1, old_gens, 1, length(s.gens))
        # This is safe, because even if the free queue allocation fails, the gens will be padded with zeros
        s.gens = new_gens
    end
    # next push idx to the free queue
    if isempty(s.free_queue)
        # initialize
        s.free_queue = fill!(Memory{UInt32}(undef, MIN_FREE_QUEUE_LEN + 1), UInt32(0))
        s.free_read_head = UInt32(0)
        s.free_write_head = UInt32(0)
    end
    i = s.free_write_head
    s.free_queue[1 + i] = idx
    i += UInt32(1)
    if i ≥ length(s.free_queue)
        i = UInt32(0)
    end
    if i == s.free_read_head
        # free queue is overfull allocate more space
        old_free_queue = s.free_queue
        old_queue_size = length(old_free_queue)
        @assert old_queue_size < Int64(2)^32 # There are at most 2^32-1 slots
        new_queue_size = Int(min(overallocation(Int64(old_queue_size)), Int64(2)^32))
        new_free_queue = fill!(Memory{UInt32}(undef, new_queue_size), UInt32(0))
        nr_data = old_queue_size%UInt32 - i + UInt32(1)
        unsafe_copyto!(new_free_queue, 1, old_free_queue, Int(i), Int(nr_data))
        unsafe_copyto!(new_free_queue, Int(nr_data) + 1, old_free_queue, 1, old_queue_size - Int(nr_data))
        s.free_read_head = UInt32(0)
        s.free_write_head = old_queue_size%UInt32
    else
        s.free_write_head = i
    end
    # We made it past the scary allocation parts!
    # finally update gens
    @assert s.gens[idx] == gen
    @assert iseven(gen)
    s.gens[idx] = gen + UInt32(1)
    @assert !iszero(s.n_active)
    s.n_active -= UInt32(1)
    s
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
Base.iterate(s::GenIDSet) = iterate(t, (; curidx=Int64(0)))

function Base.empty!(s::GenIDSet)::GenIDSet
    n = s.gens_len
    sizehint!(s, n)
    for i in 1:s.n_active
        free_id!(s, first(s))
    end
    s
end

function Base.sizehint!(s::GenIDSet, n; kwargs...)::GenIDSet
    # TODO
    s
end
