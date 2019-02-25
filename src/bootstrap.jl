using PackageCompiler
using Setfield

const build_dir = joinpath(@__DIR__,"../","build") |> abspath
const trace_dir = joinpath(@__DIR__,"../traces/") |> abspath

function start_trace()
    global trace_dir
    !isdir(trace_dir) && mkdir(trace_dir)
    trace_file = joinpath(trace_dir,"trace_$(rand(UInt32)).jl")
    opts = Base.JLOptions()
    opts = @set opts.trace_compile = convert(Ptr{UInt8},Base.unsafe_convert(Cstring,trace_file))
    unsafe_store!(Base.cglobal(:jl_options,Base.JLOptions),opts)
    return nothing
end

function grep_possible_packages(expr::Expr,package_set::Set{Symbol})
    (length(expr.args) == 0) && return
    s = expr.args[1]
    if expr.head == :.
        if typeof(s) === Symbol && s !== :.
            push!(package_set,s)
        end
    end
    foreach(expr.args) do a
        if typeof(a) == Expr
            grep_possible_packages(a,package_set)
        end
    end
    nothing
end

function bootstrap(;clear_traces = true)
    blacklist = push!(blacklist(),"Main")
    statements = Set{String}()
    packages = Set{Symbol}()
    for fname in readdir(trace_dir)
        for st in eachline(fname)
            try
                any(occursin.(blacklist,st)) && continue
                parsed = Meta.parse(st);
                grep_possible_packages(parsed,packages)
                push!(statements,st);
            catch e
                statement = st
                @info "Failed to parse statement" statement
            end
        end
    end
    out_file = joinpath(build_dir,"precomp.jl")
    @info "generating build enviorment"

    env = """
    using Pkg
    empty!(Base.LOAD_PATH)
    # Take LOAD_PATH from parent process
    append!(Base.LOAD_PATH, ["@", "@v#.#", "@stdlib"])
    Pkg.activate("/Users/tsurherman/.julia/environments/v1.1")
    Pkg.instantiate()
    """

    usings = """
    packages = $(repr(packages))
    blacklist = Vector{Symbol}()
    for Mod in Base.loaded_modules_array()
        if !Core.isdefined(@__MODULE__, nameof(Mod))
            Core.eval(@__MODULE__, Expr(:const, Expr(:(=), nameof(Mod), Mod)))
        end
    end

    for p in packages
        if isdefined(@__MODULE__,p)
            if typeof(Core.eval(@__MODULE__,p)) === Module
                already_loaded = Core.eval(@__MODULE__,p)
                @show already_loaded
                continue
            end
        end
        try
            Core.eval(@__MODULE__, :(using \$p))
            println("using \$p")

            for Mod in Base.loaded_modules_array()
                if !Core.isdefined(@__MODULE__, nameof(Mod))
                    Core.eval(@__MODULE__, Expr(:const, Expr(:(=), nameof(Mod), Mod)))
                end
            end

        catch
            @warn "could not import \$p"
            # push!(blacklist,p)
        end
    end
    """
    #dry run

    tmod = Core.eval(Main ,:(module $(gensym()) end))
    include_string(tmod,usings)

    @show blacklist

    # filtered_statements = Vector{String}()
    # for st in statements
    #     any(occursin.(String.(blacklist),st)) && continue
    #     push!(filtered_statements,st)
    # end



    line_idx = 0; missed = 0
    open(out_file, "w") do io
        println(io, """
        $env

        $usings
        # bring recursive dependencies of used packages and standard libraries into namespace

        """)
        for line in statements
            line_idx += 1
            # replace function instances, which turn up as typeof(func)().
            # TODO why would they be represented in a way that doesn't actually work?
            line = replace(line, r"typeof\(([\u00A0-\uFFFF\w_!´\.]*@?[\u00A0-\uFFFF\w_!´]+)\)\(\)" => s"\1")
            # Is this ridicilous? Yes, it is! But we need a unique symbol to replace `_`,
            # which otherwise ends up as an uncatchable syntax error
            line = replace(line, r"\b_\b" => "🐃")
            try
                expr = Meta.parse(line, raise = true)
                if expr.head != :incomplete
                    # after all this, we still need to wrap into try catch,
                    # since some anonymous symbols won't be found...
                    println(io, "try;", line, "; catch e; @info repr(e) end")
                else
                    missed += 1
                    @warn "Incomplete line in precompile file: $line"
                end
            catch e
                missed += 1
                @warn "Parse error in precompile file: $line" exception=e
            end
        end
    end
    @info "used $(line_idx - missed) out of $line_idx precompile statements"
    @eval using PackageCompiler
    @eval PackageCompiler.compile_incremental(nothing,$out_file;force = true , verbose = false)
    nothing
    @info "DONE!!"
end
