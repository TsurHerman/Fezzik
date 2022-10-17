### Fezzik

### Installation
```julia
using Pkg
pkg"add https://github.com/TsurHerman/Fezzik"
```

### Usage

one time setup

```julia
using Fezzik
Fezzik.auto_trace()
```
enables automatic tracing of compiler activity through adding itself
to the startup.jl file.
After this phase you'll need to re-launch julia , work a little bit to let Fezzik trace your routine and then:

```julia
Fezzik.brute_build_julia()
# or 
Fezzik.brute_build_local() #sysimg will be placed in the project folder
```
builds a new julia system image with all the traced statements baked into the system image resulting in a much smoother experience with julia for the small price of slightly increased loading time, If you are working with Juno's cycler mode then this price is nicely hidden from you.  

```julia
using Fezzik
blacklist("Mypkg1","Mypkg2")
```
A persistant blacklist that prevents Fezzik from precompiling statements from your currently in-development modules, as baking them into the sysimg prevents you from seeing changes you make to the code

```julia
using Fezzik
blacklist()
```
call blacklist with no arguments to see all blacklisted modules
```julia
using Fezzik
whitelist("Mypkg1","Mypkg2")
```
make white what was once black

```julia
Fezzik.auto_trace(false)
```
remove itself from the startup.jl and deletes previous traces

trace logs can be found by running the following command
```julia
abspath(dirname(pathof(Fezzik)),"../","traces") |> edit
```

### PyPlot
to enable PyPlot showing properly after it was baked into the system image
add
```julia
PyPlot.ion()
```
to your startup.jl

### Revert

every now and then you'll want to start over, just call
```julia
Fezzik.revert()
```
to go back to the beginning
