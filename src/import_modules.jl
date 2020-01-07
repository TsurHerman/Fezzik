function reveal_loaded_packages(mod)
    for Mod in Base.loaded_modules_array()
        if !Core.isdefined(mod, nameof(Mod))
            Core.eval(mod, Expr(:const, Expr(:(=), nameof(Mod), Mod)))
        end
    end
end

function import_packages!(packages,mod,deffered = Set{Symbol}())
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
            !(p in deffered) && println("trying to import $p")
            try
                Core.eval(mod, :(import $p))
                newmod = Core.eval(mod,p);
                isdefined(newmod,:__init__) && Core.eval(newmod,:__init__)()
                Fezzik.reveal_loaded_packages(mod)
                delete!(packages,p)
                println("[$p] loaded")
            catch e
                !(p in deffered) && println("failed to import $p deffering")
            end
        end
    end
    deepcopy(packages)
end

function brute_import_packages!(packages,mod,n = 10)
    deffered = Set{Symbol}()
    for i=1:n
        deffered = Fezzik.import_packages!(packages,mod,deffered)
    end
    for p in packages
        try
            Pkg.add("$p")
            Core.eval(mod, :(import $p))
            delete!(packages,p)
            for i=1:3
                deffered = Fezzik.import_packages!(packages,mod,deffered)
            end
        catch e
            @warn e
            @warn "could not import $p"
        end
    end
    !isempty(packages) && (@warn "failed to import packages" packages)
    nothing
end
