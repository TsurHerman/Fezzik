using PackageCompiler
using Setfield

const trace_dir = abspath(@__DIR__,"../traces/")
const trace_file = Vector{UInt8}()

function trace()
    global trace_dir,trace_file
    !isdir(trace_dir) && mkdir(trace_dir)

    empty!(trace_file)
    for c in joinpath(trace_dir,"trace_$(rand(UInt32)).jl")
        push!(trace_file,UInt8(c))
    end
    push!(trace_file,C_NULL)

    opts = Base.JLOptions()
    opts = @set opts.trace_compile = pointer(trace_file)
    unsafe_store!(Base.cglobal(:jl_options,Base.JLOptions),opts)
    return nothing
end

function untrace()
    global trace_dir,cstr
    opts = Base.JLOptions()
    opts = @set opts.trace_compile = C_NULL
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

try_parse_line(line,linenum,filename) = begin
    line = replace(line, r"typeof\(([\u00A0-\uFFFF\w_!´\.]*@?[\u00A0-\uFFFF\w_!´]+)\)\(\)" => s"\1")
    # Is this ridicilous? Yes, it is! But we need a unique symbol to replace `_`,
    # which otherwise ends up as an uncatchable syntax error
    line = replace(line, r"\b_\b" => "🐃")
    try
        expr = Meta.parse(line, raise = true)
        if expr.head != :incomplete
            return (line,expr,true)
        else
            @warn "skipping line with parsing error" linenum filename
            return (line,:(),false)
        end
    catch e
        @warn "skipping line with parsing error" linenum filename
        return (line,:(),false)
    end
end

macro reveal_loaded_packages()
    return quote
        for Mod in Base.loaded_modules_array()
            if !Core.isdefined(@__MODULE__, nameof(Mod))
                Core.eval(@__MODULE__, Expr(:const, Expr(:(=), nameof(Mod), Mod)))
            end
        end
    end
end

function brute_build_julia(;clear_traces = true)
    !isdir(trace_dir) && begin
        @info "no trace files found"
        return
    end
    blacklist = push!(Fezzik.blacklist(),"Main")
    statements = Set{String}()
    packages = Set{Symbol}()
    for fname in readdir(trace_dir)
        counter = 0
        fname = abspath(trace_dir,fname)
        for st in eachline(fname)
            try
                counter += 1
                any(occursin.(blacklist,st)) && continue
                (st,parsed,success) = try_parse_line(st,counter,fname);
                !success && continue
                grep_possible_packages(parsed,packages)
                push!(statements,st);
            catch e
                statement = st
                @info "Failed to parse statement" statement
            end
        end
    end

    clear_traces && isdir(trace_dir) && for f in readdir(trace_dir)
        file = joinpath(trace_dir,f)
        try
            rm(file;force = true)
        catch err
            @warn "failed to remove trace file" err file
        end
    end

    out_file = abspath(@__DIR__,"../","precomp.jl")
    @info "generating precompile"
    my_env = Base.ACTIVE_PROJECT.x

    env = """
    using Pkg
    empty!(Base.LOAD_PATH)
    # Take LOAD_PATH from parent process
    append!(Base.LOAD_PATH, ["@", "@v#.#", "@stdlib"])

    """

    usings = """
    using Pkg
    Pkg.activate()
    #Pkg.instantiate()
    using Fezzik
    packages = $(repr(packages))

    failed_packages = Vector{Symbol}()
    for p in packages
        Fezzik.@reveal_loaded_packages
        if isdefined(@__MODULE__,p)
            if typeof(Core.eval(@__MODULE__,p)) === Module
                loaded = Core.eval(@__MODULE__,p)
                println("[\$p] already loaded")
                continue
            end
        end
        try
            println("using \$p")
            Core.eval(@__MODULE__, :(using \$p))
        catch
            try
                Pkg.add("\$p")
                Core.eval(@__MODULE__, :(using \$p))
            catch e
                @warn e
                @warn "could not import \$p"
                push!(failed_packages,p)
            end
        end
    end
    """
    #dry run
    temp_mod = Module()
    include_string(temp_mod,usings)
    if my_env == nothing
        Pkg.activate()
    else
        Pkg.activate(my_env)
    end
    failed_packages = temp_mod.failed_packages
    @show failed_packages
    open(out_file, "w") do io
        println(io, """
        $env

        # bring recursive dependencies of used packages and standard libraries into namespace
        $usings

        """)
        for line in statements
            println(io, "LINE = @__LINE__;try;", line, "; catch e; @info repr(e) LINE end")
        end
    end
    @info "used $(length(statements)) precompile statements"
    @show out_file

    untrace()

    println("\n\n\n Compiling...")
    (new_syso, old_syso) = PackageCompiler.compile_incremental(nothing,out_file;force = false , verbose = false)
    @info "DONE!!"
    try
        cp(new_syso, old_syso, force = true)
    catch err
        @warn "Failed to replace sysimg" err
        println()
        println("exit all julia sessions and manually run the following command: ")
        copy_com = Sys.iswindows() ? "copy" : "cp"
        println("$copy_com $new_syso $old_syso")
        println()
    end
    exit()
    nothing
end
export brute_build_julia

using Libdl
sysimage_size() = stat(joinpath(PackageCompiler.default_sysimg_path(),"sys.$(Libdl.dlext)")).size/(1024*1024)
export sysimage_size

const revert = PackageCompiler.revert
