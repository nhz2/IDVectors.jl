# UniqueIDs (WIP)

This package is not registered yet and its API and testing is still a work in progress.

[![Test workflow status](https://github.com/nhz2/UniqueIDs.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/nhz2/UniqueIDs.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/nhz2/UniqueIDs.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/nhz2/UniqueIDs.jl)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

AbstractVectors of unique Int64 IDs to help keep track of collections of things with identity.

## Example usage

```julia
using StructArrays
using UniqueIDs
using Tests

struct Foo
    neighbor::Int64
    mass::Float64
end

# First we create an empty vector of structs with neighbors and masses.

data = StructVector(Foo[])
ids = Dyn()

# `sizehint!` can be used to preallocate

sizehint!(data, 10)
sizehint!(ids, 10)

# Now adds some things with neighbors set to zero as a placeholder
push!(data, Foo(0, 1.5))
id1 = alloc_id!(ids)
push!(data, Foo(0, 2.5))
id2 = alloc_id!(ids)
push!(data, Foo(0, 3.5))
id3 = alloc_id!(ids)
push!(data, Foo(0, 4.5))
id4 = alloc_id!(ids)

# Now connect things up using the ids
data.neighbor[1] = id2
data.neighbor[2] = id1
data.neighbor[3] = id4
data.neighbor[4] = id3

# Return `id`'s neighbor's mass
function neighbors_mass(data, ids, id)
    nid = data.neighbor[id2idx(ids, id)]
    data.mass[id2idx(ids, nid)]
end

@test neighbors_mass(data, ids, id1) == 2.5

# Now delete the connected pair id1 and id2
# swap_deleteat! is in general a faster than deleteat! because it doesn't need to shift everything.
UniqueIDs.swap_deleteat!(data, free_id!(ids, id1))
UniqueIDs.swap_deleteat!(data, free_id!(ids, id2))

# Trying to read from a deleted id will error
@test_throws KeyError(id1) neighbors_mass(data, ids, id1)

# But id3 and id4 are still there and still have valid ids
@test neighbors_mass(data, ids, id3) == 4.5

# If new pairs are added, ids will try to avoid reusing old ids
# However, eventually there will be a wrap around. For `Dyn` this requires
# about 2^63 ids to be used.
id5 = alloc_id!(ids)
id6 = alloc_id!(ids)
push!(data, Foo(id6, 5.5))
push!(data, Foo(id5, 6.5))

@test allunique([id1, id2, id3, id4, id5, id6])

@test_throws KeyError(id1) neighbors_mass(data, ids, id1)
```







## Related packages

https://github.com/Tortar/KeyedTables.jl/tree/main
https://github.com/garrison/UniqueVectors.jl
https://github.com/andyferris/AcceleratedArrays.jl
https://github.com/JuliaData/TypedTables.jl

https://docs.rs/slotmap/1.0.7/slotmap/index.html
https://docs.rs/slotmap-careful/latest/slotmap_careful/
https://docs.rs/thunderdome/latest/thunderdome/

