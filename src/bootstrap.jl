using PackageCompiler
using Setfield
using Pkg

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
    opts = @set opts.compile_enabled = 2
    unsafe_store!(Base.cglobal(:jl_options,Base.JLOptions),opts)
    return nothing
end

function untrace()
    global trace_dir,cstr
    opts = Base.JLOptions()
    opts = @set opts.trace_compile = C_NULL
    opts = @set opts.compile_enabled = 1
    unsafe_store!(Base.cglobal(:jl_options,Base.JLOptions),opts)
    return nothing
end

function grep_possible_packages!(package_set::Set{Symbol},expr::Expr)
    (length(expr.args) == 0) && return
    s = expr.args[1]
    if expr.head == :.
        if typeof(s) === Symbol && s !== :.
            push!(package_set,s)
        end
    end
    foreach(expr.args) do a
        if typeof(a) == Expr
            grep_possible_packages!(package_set,a)
        end
    end
    nothing
end

semantic_fix(line) = begin
    line = replace(line,"(\"" => "(raw\"")
    line = replace(line,"DatePart{Char(" => "DatePart{(")
    line = replace(line,r"(?<!#)#s(?=\d)" => "T")
    line = replace(line,")()" => ")")
end

try_parse_line(line,linenum = 0,filename ="") = begin
    try
        expr = Meta.parse(line, raise = true)
        if expr.head != :incomplete
            return expr
        else
            @warn "skipping line with parsing error" linenum filename
            return nothing
        end
    catch e
        @warn "skipping line with parsing error" linenum filename
        return nothing
    end
end

function brute_build_julia(;clear_traces = true , debug = false)
    !isdir(trace_dir) && begin
        @info "no trace files found"
        return
    end
    blacklist = push!(Fezzik.blacklist(),"Main","##benchmark#","###compiledcall")
    statements = Set{String}()
    packages = Set{Symbol}()
    for fname in readdir(trace_dir)
        counter = 0
        fname = abspath(trace_dir,fname)
        for line in eachline(fname)
            try
                counter += 1
                any(occursin.(blacklist,[line])) && continue
                line = semantic_fix(line);
                expr = try_parse_line(line,counter,fname);
                isnothing(expr) && continue
                grep_possible_packages!(packages,expr)
                push!(statements,line);
            catch e
                statement = line
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
    import Pkg
    empty!(Base.LOAD_PATH)
    # Take LOAD_PATH from parent process
    append!(Base.LOAD_PATH, ["@", "@v#.#", "@stdlib"])
    import Random
    Base.PCRE.__init__()
    Random.__init__()

    """

    usings = """
    import Pkg
    Pkg.activate()
    import Fezzik
    packages = $(repr(packages))
    Fezzik.brute_import_packages!(packages,@__MODULE__)

    """
    #dry run
    temp_mod = Module()
    include_string(temp_mod,usings)
    if my_env == nothing
        Pkg.activate()
    else
        Pkg.activate(my_env)
    end

    open(out_file, "w") do io
        println(io, """
        $env

        # recursively bring dependencies of used packages and standard libraries into namespace
        $usings

        """)
        for line in statements

            reporter = debug ? """ println("\$(@__FILE__):\$LINE") """ : """ print("compiling line \$LINE\\r") """

            println(io, """
            let LINE = @__LINE__;
            try $line;
                $reporter;
            catch e; println(); @info repr(e) LINE end end
            """)
        end

        println(io, """
            println();
            println("done.")
            println(".")
            println(".")
            println("Creating sysimg")
        """)

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

import Libdl
sysimage_size() = stat(joinpath(PackageCompiler.default_sysimg_path(),"sys.$(Libdl.dlext)")).size/(1024*1024)
export sysimage_size

revert(;force = false) = begin
    force && rm(PackageCompiler.sysimgbackup_folder(); force = true, recursive = true)
    PackageCompiler.revert(false)
end

clean() = begin
    rm(PackageCompiler.sysimgbackup_folder();force = true,recursive = true);
    PackageCompiler.force_native_image!();
end
