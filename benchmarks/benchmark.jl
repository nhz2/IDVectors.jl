#!/usr/bin/env -S OPENBLAS_NUM_THREADS=1 JULIA_LOAD_PATH=@ julia --project=@script --threads=1 --startup-file=no

# This script plots benchmark results to a `benchmark.png` file
# in the working directory

using Chairmarks
using UniqueIDs
using Random
using Statistics

"""
    Setup a `size` length vector
    after `size*fract_shuffled` random free and alloc pairs
"""
function setup_ids(type::T, size, fract_shuffled) where T
    ids = type()
    n_del_push = round(Int, size*fract_shuffled)
    for i in 1:size
        alloc_id!(ids)
    end
    for i in 1:n_del_push
        id = rand(ids)
        free_id!(ids, id)
        alloc_id!(ids)
    end
    ids
end

function bench_rand_access(type::T, size, fract_shuffled) where T
    ids = setup_ids(type, size, fract_shuffled)
    shuffled_ids = shuffle(collect(ids))
    @be(ids(rand(shuffled_ids)), seconds=2)
end

function bench_rand_in(type, size, fract_shuffled)
    ids = setup_ids(type, size, fract_shuffled)
    @be(rand(Int64) ∈ ids, seconds=2)
end

function bench_rand_deletes(type, size, fract_shuffled, n_deletes)
    @be(
        let
            ids = setup_ids(type, size, fract_shuffled)
            shuffled_ids = shuffle(collect(ids))
            (ids, shuffled_ids)
        end,
        (x)->let
            for i in 1:n_deletes
                free_id!(x[1], x[2][i])
            end
        end,
        evals=1,
        seconds=2,
    )
end

function bench_pushes(type, size, fract_shuffled, n_pushes)
    @be(
        setup_ids(type, size, fract_shuffled),
        (x)->let
            for i in 1:n_pushes
                alloc_id!(x)
            end
        end,
        evals=1,
        seconds=2,
    )
end

using CairoMakie

function save_benchmark_plots(;
        outdir= pwd(),
        ntrials= 3,
    )
    datatypes = [
        Inc,
        Gen,
        GenNoWrap,
        Dyn,
    ]
    datatype_markers = [
        :circle,
        :cross,
        :xcross,
        :star5,
    ]
    # Test parameters
    sizes = Int[
        1E4,
        1E5,
        1E6,
        1E7,
    ]
    fract_shuffled_values = [2.0]

    fig = Figure(size = (1200, 800))

    subplot_titles = [
        "Random id2idx Performance",
        "Random in Performance",
        "Delete Performance",
        "Push Performance",
    ]
    subplot_positions = [
        (1,1),
        (1,2),
        (2,1),
        (2,2),
    ]
    subplot_functions = [
        x -> mean(bench_rand_access(x.dtype, x.size, x.fract_shuffled)).time*1E9,
        x -> mean(bench_rand_in(x.dtype, x.size, x.fract_shuffled)).time*1E9,
        x -> mean(bench_rand_deletes(x.dtype, x.size, x.fract_shuffled, x.size)).time*1E9/x.size,
        x -> mean(bench_pushes(x.dtype, 100, x.fract_shuffled, x.size)).time*1E9/x.size,
    ]
    for subplot_i in 1:4
        ax = Axis(fig[subplot_positions[subplot_i]...],
            title = subplot_titles[subplot_i],
            xlabel = "Vector Size", 
            ylabel = "Time per op (ns)",
            xscale = log10,
            limits = ((nothing,nothing), (0.0,nothing)),
        )
        @info ax.title[]
        out = Dict()
        for trial in 1:ntrials
            for (i, dtype) in enumerate(datatypes)
                for fract_shuffled in fract_shuffled_values
                    test_options = (;i, dtype, fract_shuffled)
                    positions = get!(out, test_options, [])
                    for size in sizes
                        result = subplot_functions[subplot_i]((;dtype, size, fract_shuffled))
                        # jitter position horizontally to avoid overlap
                        push!(positions, (size*(0.90+0.2*rand()), result))
                    end
                end
            end
        end
        for (test_options, positions) in sort(pairs(out))
            test_name = ("$(test_options.dtype) $(test_options.fract_shuffled*100)% shuffled")
            scatter!(ax, positions; label= test_name, marker= datatype_markers[test_options.i])
        end
        if subplot_i == 1
            Legend(fig[1,3], ax)
        end
    end

    # # Save the plot
    outpath = joinpath(outdir, "benchmark.png")
    save(outpath, fig)
    println("Benchmark plots saved to $(repr(outpath))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    save_benchmark_plots()
end
