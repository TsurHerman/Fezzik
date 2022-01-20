using PackageCompiler
using Setfield
using Pkg
using Random

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

brute_build_local() = brute_build_julia(replace = false)
export brute_build_local

function brute_build_julia(;clear_traces = true, replace = true)
    !isdir(trace_dir) && begin
        @info "no trace files found"
        return
    end
    if Sys.isunix()
        ENV["JULIA_CC"] = "/usr/bin/gcc"
    end
    blacklist = push!(Fezzik.blacklist(),"Main","##benchmark#","###compiledcall","VSCode")
    statements = Set{String}()
    packages = Set{Symbol}()
    for fname in readdir(trace_dir)
        counter = 0
        fname = abspath(trace_dir,fname)
        for line in eachline(fname)
            try
                counter += 1
                any(occursin.(blacklist,[line])) && continue
                # line = semantic_fix(line);
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

    out_file = abspath(@__DIR__,"../","precomp.jl")
    @info "generating precompile"

    for pkg in packages
        @eval import $pkg
    end
    @info "dry run3"
    statements = filter(shuffle(collect(statements))) do st
        try 
            res = eval(Meta.parse(st))
            if !res
                @warn st
            end
            return res
        catch err
            @show err
            return false
        end
    end

    open(out_file, "w") do io
        for pkg in packages
            println(io, "import $(pkg)")
        end
        for line in statements
            println(io, "$line")
        end
    end
    @info "used $(length(statements)) precompile statements"
    @show out_file
    compile_incremental(packages,out_file,replace)
    @info "DONE!!"

    clear_traces && isdir(trace_dir) && for f in readdir(trace_dir)
        file = joinpath(trace_dir,f)
        try
            rm(file;force = true)
        catch err
            @warn "failed to remove trace file" err file
        end
    end

    exit()
    nothing
end
export brute_build_julia

import Libdl
sysimage_size() = stat(unsafe_string(Base.JLOptions().image_file)).size/1024/1024
export sysimage_size

revert(;force = false) = begin
    PackageCompiler.restore_default_sysimage()
end


compile_incremental(packages,file,replace) = begin
    packages = filter(collect(packages)) do mod
        mod == :Base ? false : mod == :Core ? false : true
    end

    missing_packages = packages_not_in_project(project_ctx(),packages)
    try Pkg.add(missing_packages) catch err
        unresolved = map(x->String(x[1]),eachmatch(r"[*] (\w+)",err.msg))
        @show unresolved
        packages = setdiff(packages,Symbol.(unresolved))
        missing_packages = setdiff(missing_packages,unresolved)
        !isempty(missing_packages)  && Pkg.add(missing_packages)
    end

    @show Base.JLOptions().image_file |> unsafe_string |> deepcopy
    if replace
        PackageCompiler.create_sysimage(packages; precompile_statements_file = file , replace_default = true)
    else
        PackageCompiler.create_sysimage(packages; precompile_execution_file = file , sysimage_path = pwd() * "/JuliaSysimage." * PackageCompiler.Libdl.dlext,
        base_sysimage = Base.JLOptions().image_file |> unsafe_string |> deepcopy , include_transitive_dependencies = false, sysimage_build_args = `-O2 --check-bounds=no`)
    end     
end

function packages_not_in_project(ctx, packages)
    packages_in_project = collect(keys(ctx.env.project.deps))
    if ctx.env.pkg !== nothing
        push!(packages_in_project, ctx.env.pkg.name)
    end
    setdiff(string.(packages), packages_in_project)
end

function project_ctx(project = dirname(Base.active_project()))
    @show project
    project_toml_path = Pkg.Types.projectfile_path(project; strict=true)
    if project_toml_path === nothing
        error("could not find project at $(repr(project))")
    end
    return Pkg.Types.Context(env=Pkg.Types.EnvCache(project_toml_path))
end
