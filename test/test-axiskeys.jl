using IDVectors
using AxisKeys

struct Foo
    bar::Float64
    baz::Int
end

data = KeyedArray(Foo[], DynIDVector())

push!(data, Foo(1.0, 3))

@test pop!(data) == Foo(1.0, 3)

push!(data, Foo(2.0, 3), Foo(3.0, 3))

@test pop!(data) == Foo(3.0, 3)

@test pop!(data) == Foo(2.0, 3)