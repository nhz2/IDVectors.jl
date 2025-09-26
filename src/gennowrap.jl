"""
The 32 most significant bits of an id is the generation. Even generations are active, odd generations are inactive.
The 32 least significant bits of an id is an index.
id's are never zero.
IDs never wrap around but 4 bytes are leaked every 2^31 pairs of alloc and free.
"""
mutable struct GenNoWrapIDSet <: IDSet
    gens::Memory{UInt32}
    gens_len::UInt32
    n_active::UInt32
    free_stack::Memory{UInt32}
    free_len::UInt32
end

function GenNoWrapIDSet()
    GenNoWrapIDSet(
        Memory{UInt32}(undef, 0),
        UInt32(0),
        UInt32(0),
        Memory{UInt32}(undef, 0),
        UInt32(0),
    )
end

function assert_invariants(s::GenNoWrapIDSet)
    @assert s.n_active ≤ s.gens_len
    n_inactive = count(isodd, view(s.gens, 1:min(s.gens_len, length(s.gens))))
    n_dead = count(==(typemax(UInt32)), view(s.gens, 1:min(s.gens_len, length(s.gens))))
    @assert n_inactive == s.gens_len - s.n_active
    @assert Int64(s.gens_len) == Int64(s.n_active) + n_dead + Int64(s.free_len)
    # check the free stack is valid
    @assert allunique(s.free_stack[1:s.free_len])
    for i in 1:s.free_len
        @assert isodd(s.gens[s.free_stack[i]])
        s.gens[s.free_stack[i]] != typemax(UInt32)
    end
    @assert length(s.gens) ≤ typemax(UInt32)
    for i in s.gens_len+1:length(s.gens)
        @assert iszero(s.gens[i])
    end
end

function next_id(s::GenNoWrapIDSet)::Int64
    gens_len = s.gens_len
    free_len = s.free_len
    if iszero(free_len)
        # No free slots make a new one with implicit generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        Int64(gens_len + UInt32(1))
    else
        # Pick a slot off the free stack
        f = s.free_stack[free_len]
        new_gen = s.gens[f] + UInt32(1)
        Int64(new_gen)<<32 | Int64(f)
    end
end

function alloc_id!(s::GenNoWrapIDSet)::Int64
    gens_len = s.gens_len
    free_len = s.free_len
    if iszero(free_len)
        # No free slots make a new one with implicit generation 0
        if gens_len == typemax(UInt32)
            throw(OverflowError("next_id would wraparound"))
        end
        s.gens_len += UInt32(1)
        s.n_active += UInt32(1)
        Int64(s.gens_len)
    else
        # Pick a slot off the free stack
        f = s.free_stack[free_len]
        new_gen = s.gens[f] + UInt32(1)
        s.gens[f] = new_gen
        s.n_active += UInt32(1)
        s.free_len -= UInt32(1)
        Int64(new_gen)<<32 | Int64(f)
    end
end

# Expand the size of s.gens to at least n
function _grow_gens!(s::GenNoWrapIDSet, n::Int64)
    old_gens = s.gens
    if n ≤ length(old_gens)
        return
    end
    @assert n ∈ length(old_gens) + 1 : Int64(typemax(UInt32))
    new_size = Int(min(overallocation(n), Int64(typemax(UInt32))))
    new_gens = fill!(Memory{UInt32}(undef, new_size), UInt32(0))
    unsafe_copyto!(new_gens, 1, old_gens, 1, length(old_gens))
    s.gens = new_gens
    return
end

# Expand the size of s.free_stack to be able to store at least n free slots
function _grow_free_stack!(s::GenNoWrapIDSet, n::Int64)
    old_free_stack = s.free_stack
    if n ≤ length(old_free_stack)
        return
    end
    @assert n ∈ length(old_free_stack) + 1 : Int64(typemax(UInt32))
    new_size = Int(min(overallocation(n), Int64(typemax(UInt32))))
    new_free_stack = fill!(Memory{UInt32}(undef, new_size), UInt32(0))
    unsafe_copyto!(new_free_stack, 1, old_free_stack, 1, length(old_free_stack))
    s.free_stack = new_free_stack
    return
end

function free_id!(s::GenNoWrapIDSet, id::Int64)::GenNoWrapIDSet
    if id ∉ s
        throw(KeyError(id))
    end
    idx = id%UInt32
    gen = (id>>>32)%UInt32
    new_gen = gen + UInt32(1)
    # Do the memory allocations first to avoid corrupting s in case that errors
    _grow_gens!(s, Int64(idx))
    if new_gen !=  typemax(UInt32)
        _grow_free_stack!(s, s.free_len + Int64(1))
    end
    # We made it past the scary allocation parts!
    # next push idx to the free stack
    # to avoid overflow avoid adding to free stack
    # if the new_gen is typemax(UInt32)
    if new_gen != typemax(UInt32)
        s.free_stack[s.free_len+1] = idx
        s.free_len += UInt32(1)
    end
    # finally update gens
    s.gens[idx] = new_gen
    @assert !iszero(s.n_active)
    s.n_active -= UInt32(1)
    s
end

function reset!(s::GenNoWrapIDSet)::GenNoWrapIDSet
    s.gens = Memory{UInt32}(undef, 0)
    s.gens_len = UInt32(0)
    s.n_active = UInt32(0)
    s.free_stack = Memory{UInt32}(undef, 0)
    s.free_len = UInt32(0)
    s
end

# Functions from Base

function Base.in(id::Int64, s::GenNoWrapIDSet)::Bool
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

Base.length(s::GenNoWrapIDSet) = Int(s.n_active)
function Base.iterate(s::GenNoWrapIDSet, state::NamedTuple)
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
Base.iterate(s::GenNoWrapIDSet) = iterate(s, (; curidx=Int64(0)))

function Base.empty!(s::GenNoWrapIDSet)::GenNoWrapIDSet
    n = s.gens_len
    _grow_gens!(s, Int64(n))
    _grow_free_stack!(s, Int64(s.free_len + s.n_active))
    for idx in UInt32(1):n
        gen = s.gens[idx]
        if iseven(gen)
            new_gen = gen + UInt32(1)
            if new_gen != typemax(UInt32)
                s.free_stack[1 + s.free_len] = idx
                s.free_len += UInt32(1)
            end
            s.gens[idx] = gen + UInt32(1)
        end
    end
    s.n_active = UInt32(0)
    s
end

function Base.sizehint!(s::GenNoWrapIDSet, n; kwargs...)::GenNoWrapIDSet
    _n = clamp(n, 0, Int64(typemax(UInt32)))%Int64
    _grow_gens!(s, _n)
    _grow_free_stack!(s, _n)
    s
end
