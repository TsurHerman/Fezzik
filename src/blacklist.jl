const blacklist_file = joinpath(@__DIR__,"../blacklist") |> abspath

function read_blacklist()
    list = Set{String}()
    !isfile(blacklist_file) && return list
    for mod in eachline(blacklist_file)
        push!(list,mod)
    end
    return list
end

function write_blacklist(list::Set{String})
    open(blacklist_file,"w") do io
        for s in list
            println(io,s)
        end
    end
end

function blacklist(mods::String...)
    list = read_blacklist()
    for mod in mods
        push!(list,mod)
    end
    write_blacklist(list)
    list
end

function whitelist(mods::String...)
    list = blacklist()
    for mod in mods
        (mod in list) && pop!(list,mod)
    end
    write_blacklist(list)
    list
end

whitelist(mods) = whitelist(mods...)

export whitelist,blacklist
