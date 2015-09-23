# AmplNLWriter.jl

This [Julia](https://github.com/JuliaLang/julia) package is an interface between [MathProgBase.jl](https://github.com/JuliaOpt/MathProgBase.jl) and [AMPL-enabled](http://www.ampl.com) [solvers](http://ampl.com/products/solvers/all-solvers-for-ampl/). It is similar in nature to [CoinOptServices.jl](https://github.com/tkelman/CoinOptServices.jl), but instead uses AMPL's low-level [.nl](https://en.wikipedia.org/wiki/Nl_%28format%29) file format.

A list of AMPL-enabled solvers is available [here](http://ampl.com/products/solvers/all-solvers-for-ampl/).

## Installation

AmplNLWriter.jl can be installed using the Julia package manager with the following command:

```julia
Pkg.add("AmplNLWriter")
```

## Usage

AmplNLWriter.jl provides ``AmplNLSolver`` as a usable solver in JuMP. The following Julia code uses the Bonmin solver in JuMP via AmplNLWriter.jl:

    julia> using JuMP, AmplNLWriter
    julia> m = Model(solver=AmplNLSolver("bonmin"), "-s")

You can then model and solve your optimization problem as usual. See [JuMP's documentation](http://jump.readthedocs.org/en/latest/) for more details. 

The ``AmplNLSolver()`` constructor requires as the first argument the name of the solver command needed to run the desired solver. For example, if the ``bonmin`` executable is on the system path, you can use this solver using ``AmplNLSolver("bonmin")``. If the solver is not on the path, the full path to the solver will need to be passed in. This solver executable must be an AMPL-compatible solver.

The second and third arguments to ``AmplNLSolver()``, `pre_command` and `post_command`, are optional strings that are specific to the solver you are using. ``AmplNLSolver`` will execute the following command when running the solver:

    solver_command pre_command /path/to/model.nl post_command <options>

For example, Bonmin needs to be run as follows:

    bonmin -s /path/to/model.nl

So we need to set `pre_command="-s"` and `post_command=""`. SCIP using the `scipampl` binary is run with:

    scipampl /path/to/model.nl

So both `pre_command` and `post_command` are `""`.

For other solvers, you will need to determine the appropriate form for invoking the solver and set `pre_command` and `post_command` yourself.

The final (optional) argument to ``AmplNLSolver()`` is a ``Dict{String, Any}`` of solver options. These should be specified with the name of the option as the key, and the desired value as the value. For example, to set the NLP log level to 0 in Bonmin, you would run ``AmplNLSolver("bonmin", "-s", "", Dict("bonmin.nlp_log_level"=>0))``. For a list of options supported by your solver, check the solver's documentation, or run ``/path/to/solver -=`` at the command line e.g. run ``bonmin -=`` for a list of all Bonmin options.

If you have [CoinOptServices.jl](https://github.com/JuliaOpt/CoinOptServices.jl) installed, you can easily use the Bonmin or Couenne solvers installed by this package:

- Bonmin: ``BonminNLSolver(options)``
- Couenne: ``CouenneNLSolver(options)``

Similarly, if you have [Ipopt.jl](https://github.com/JuliaOpt/Ipopt.jl) installed, you can use Ipopt by using the solver `IpoptNLSolver(options)`.

In the `examples` folder you can see a range of problems solved using this package via JuMP.

The AmplNLSolver should also work with any other MathProgBase-compliant linear or nonlinear optimization modeling tools, though this has not been tested.

