const total_statements = Ref(0)
const succesful = Ref(0)

macro compile(statement)
    global succesful,total_statements
    total_statements[] += 1
    printstyled("compiling statement $(total_statements[]) \r",color = :reverse)
    try
        succesful[] +=  Base.eval(__module__,statement)
    catch error
        printstyled("\nWarning: ",bold = true , color = :yellow);
        printstyled("parsing error\n");
        @show error
        printstyled("$(__source__.file):$(__source__.line)\n\n",color=:cyan)
    end
end

reset_count() = begin
    succesful[] = 0
    total_statements[] = 0;
end

compile_summary() = begin
    printstyled("\n\nDONE: ",bold = true , color = :yellow);
    print("$(succesful[]) out of $(total_statements[]) succesfully compiled\n");
    printstyled("\nCreating sysimg...\n",bold = true , color = :red);
end
