# Copied from base/array.jl because this is not a public function
# Modified to use Int64 and to have max to prevent overflow
# https://github.com/JuliaLang/julia/blob/v1.11.6/base/array.jl#L1042-L1056
# Pick new memory size for efficiently growing an array
# TODO: This should know about the size of our GC pools
# Specifically we are wasting ~10% of memory for small arrays
# by not picking memory sizes that max out a GC pool
function overallocation(maxsize::Int64)::Int64
    maxsize < 8 && return Int64(8);
    # compute maxsize = maxsize + 4*maxsize^(7/8) + maxsize/8
    # for small n, we grow faster than O(n)
    # for large n, we grow at O(n/8)
    # and as we reach O(memory) for memory>>1MB,
    # this means we end by adding about 10% of memory each time
    exp2 = sizeof(maxsize) * 8 - Core.Intrinsics.ctlz_int(maxsize)
    newsize = maxsize + (1 << div(exp2 * 7, 8)) * 4 + div(maxsize, 8)
    return max(maxsize, newsize)
end

@inline function _grow_fill_field!(s, n::Int64, field::Symbol, maxsize::Int64= typemax(Int64))
    old_mem = getfield(s, field)
    if n ≤ length(old_mem)
        return
    end
    new_size = Int(min(overallocation(n), maxsize))
    new_mem = typeof(old_mem)(undef, new_size)
    unsafe_copyto!(new_mem, 1, old_mem, 1, length(old_mem))
    setfield!(s, field, new_mem)
    return
end
