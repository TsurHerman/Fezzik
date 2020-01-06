function reveal_loaded_packages(mod)
    for Mod in Base.loaded_modules_array()
        if !Core.isdefined(mod, nameof(Mod))
            Core.eval(mod, Expr(:const, Expr(:(=), nameof(Mod), Mod)))
        end
    end
end

function import_packages!(packages,mod)
    for p in packages
        Fezzik.reveal_loaded_packages(mod)
        if isdefined(mod,p)
            if typeof(Core.eval(mod,p)) === Module
                Core.eval(mod,p)
                println("[$p] already loaded")
                delete!(packages,p)
            else
                println("[$p] is not a Module")
            end
        else
            println("trying to import $p")
            try
                Core.eval(mod, :(import $p))
                Fezzik.reveal_loaded_packages(mod)
                delete!(packages,p)
                println("[$p] loaded")
            catch e
                println("failed to import $p deffering")
            end
        end
    end
end

function brute_import_packages!(packages,mod,n = 10)
    for i=1:n
        Fezzik.import_packages!(packages,mod)
    end
    for p in packages
        try
            Pkg.add("$p")
            Core.eval(mod, :(import $p))
            delete!(packages,p)
            Fezzik.import_packages!(packages,mod)
        catch e
            @warn e
            @warn "could not import $p"
        end
    end
    !isempty(packages) && (@warn "failed to import packages" packages)
    nothing
end
