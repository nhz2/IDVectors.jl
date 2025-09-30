module AxisKeysExt

import AxisKeys
using UniqueIDs

function AxisKeys.extend_one!!(s::UniqueIDs.UniqueID)
    alloc_id!(s)
    s
end

extend_by!!(r::Vector{<:Number}, n::Int) = append!(r, length(r)+1 : length(r)+n+1)

function AxisKeys.extend_by!!(s::UniqueIDs.UniqueID, n::Int)
    for i in 1:n
        alloc_id!(s)
    end
    s
end

function AxisKeys.shorten_one!!(s::UniqueIDs.UniqueID)
    pop!(s)
    s
end

Base.@propagate_inbounds function swap!(A::AxisKeys.KeyedVector, a::Int, b::Int)
    swap!(axiskeys(A,1), a, b)
    swap!(parent(A), a, b)
    s
end

end