
function julia_startup_file()
    res = abspath(homedir(), ".julia", "config", "startup.jl")
    !isfile(res) && touch(res)
    res
end

function StartupTracer()
    """
    # FezzikAutoGenStart
    # to remove remove entire block
    try
        using Fezzik
        try
            Fezzik.trace()
        catch err
            @info "Something went wrong" err
        end
    catch e
        try
            using Pkg
            Pkg.add("Fezzik")
            import Fezzik
            try
                Fezzik.trace()
            catch err
                @info "Something went wrong" err
            end
        catch err
            @info "Something went wrong" err
        end
    end

    # FezzikAutoGenEnd
    """
end
function auto_trace(b::Bool = true)
    auto_trace(Val(b))
end

function auto_trace(::Val{true})
    startup = read(julia_startup_file(),String)
    !occursin("FezzikAutoGenStart",startup) &&
        (startup = StartupTracer() * "\n" * startup)
    open(julia_startup_file(),"w") do io
        println(io,startup)
    end
end

function auto_trace(::Val{false})
    skip = false
    startup = Vector{String}()
    for line in eachline(julia_startup_file())
        occursin("FezzikAutoGenStart",line) && (skip = true)
        if occursin("FezzikAutoGenEnd",line)
            skip = false
            continue;
        end
        !skip && push!(startup,line)
    end
    open(julia_startup_file(),"w") do io
        for line in startup
            println(io,line)
        end
    end
    rm(trace_dir;force=true , recursive = true)
    nothing
end
