# AmplNlWriter.jl

This [Julia](https://github.com/JuliaLang/julia) package is an interface between [MathProgBase.jl](https://github.com/JuliaOpt/MathProgBase.jl) and [AMPL-enabled](http://www.ampl.com) [solvers](http://ampl.com/products/solvers/all-solvers-for-ampl/), translating between the [Julia-expression-tree MathProgBase format](http://mathprogbasejl.readthedocs.org/en/latest/nlp.html#obj_expr) for nonlinear objective and constraint functions and AMPL's low-level [.nl](https://en.wikipedia.org/wiki/Nl_%28format%29) optimization problem interchange format.

By writing .nl files this package allows Julia optimization modeling languages such as [JuMP](https://github.com/JuliaOpt/JuMP.jl) to access any solver that has an AMPL interface. This includes the COIN-OR solvers [Clp](https://projects.coin-or.org/Clp) (linear programming), [Cbc](https://projects.coin-or.org/Cbc) (mixed-integer linear programming), [Ipopt](https://projects.coin-or.org/Ipopt) (nonlinear programming), [Bonmin](https://projects.coin-or.org/Bonmin) (evaluation-based mixed-integer nonlinear programming), [Couenne](https://projects.coin-or.org/Couenne) (expression-tree-based mixed-integer nonlinear programming), and several others.

You can obtain AMPL-enabled versions of the COIN-OR solvers from [AMPL](http://ampl.com/products/solvers/open-source/).

Note that [Clp](https://github.com/JuliaOpt/Clp.jl), [Cbc](https://github.com/JuliaOpt/Cbc.jl), and [Ipopt](https://github.com/JuliaOpt/Ipopt.jl) already have Julia packages that interface directly with their respective in-memory C API's. Particularly for Clp.jl and Cbc.jl, the existing packages should be faster than the CoinOptServices.jl approach of going through a .nl file on disk.Ipopt may or may not be faster using AmplNlWriter.jl than Ipopt.jl, which uses the pure-Julia [ReverseDiffSparse.jl](https://github.com/mlubin/ReverseDiffSparse.jl) package used for nonlinear programming in JuMP. TODO: benchmarking!

## Installation

AmplNlWriter.jl is not a listed package (yet). You can install with the following command:

```julia
Pkg.clone("https://github.com/JackDunnNZ/AmplNlWriter.jl")
```

## Usage

AmplNlWriter.jl provides ``AmplNlSolver`` as a usable solver in JuMP. The following Julia code uses the Bonmin solver in JuMP via AmplNlWriter.jl:

    julia> using JuMP, AmplNlWriter
    julia> m = Model(solver=AmplNlSolver("bonmin"))

You can then model and solve your optimization problem as usual. See [JuMP's documentation](http://jump.readthedocs.org/en/latest/) for more details. 

The ``AmplNlSolver()`` constructor requires as the first argument the name of the solver command needed to run the desired solver. For example, if the ``bonmin`` executable is on the system path, you can use this solver using ``AmplNlSolver("bonmin")``. If the solver is not on the path, the full path to the solver will need to be passed in. This solver executable must be an AMPL-compatible solver.

The second (optional) argument to ``AmplNlSolver()`` is a ``Dict{String, Any}`` of solver options. These should be specified with the name of the option as the key, and the desired value as the value. For example, to set the NLP log level to 0 in Bonmin, you would run ``AmplNlSolver("bonmin", ["bonmin.nlp_log_level"=>0])``. For a list of options supported by your solver, check the solver's documentation, or run ``/path/to/solver -=`` at the command line e.g. run ``bonmin -=`` for a list of all Bonmin options.

In the `examples` folder you can see a range of problems solved using this package via JuMP.

The AmplNlSolver should also work with any other MathProgBase-compliant linear or nonlinear optimization modeling tools, though this has not been tested.

