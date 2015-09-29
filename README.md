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
    julia> m = Model(solver=AmplNLSolver("bonmin"))

You can then model and solve your optimization problem as usual. See [JuMP's documentation](http://jump.readthedocs.org/en/latest/) for more details. 

The ``AmplNLSolver()`` constructor requires as the first argument the name of the solver command needed to run the desired solver. For example, if the ``bonmin`` executable is on the system path, you can use this solver using ``AmplNLSolver("bonmin")``. If the solver is not on the path, the full path to the solver will need to be passed in. This solver executable must be an AMPL-compatible solver.

The second (optional) argument to ``AmplNLSolver()`` is a ``Dict{String, Any}`` of solver options. These should be specified with the name of the option as the key, and the desired value as the value. For example, to set the NLP log level to 0 in Bonmin, you would run ``AmplNLSolver("bonmin", Dict("bonmin.nlp_log_level"=>0))``. For a list of options supported by your solver, check the solver's documentation, or run ``/path/to/solver -=`` at the command line e.g. run ``bonmin -=`` for a list of all Bonmin options.

If you have [CoinOptServices.jl](https://github.com/JuliaOpt/CoinOptServices.jl) installed, you can easily use the Bonmin or Couenne solvers installed by this package:

- Bonmin: ``BonminNLSolver(options)``
- Couenne: ``CouenneNLSolver(options)``

Similarly, if you have [Ipopt.jl](https://github.com/JuliaOpt/Ipopt.jl) installed, you can use Ipopt by using the solver `IpoptNLSolver(options)`.

In the `examples` folder you can see a range of problems solved using this package via JuMP.

The AmplNLSolver should also work with any other MathProgBase-compliant linear or nonlinear optimization modeling tools, though this has not been tested.

### Checking solve results

In addition to returning the status via `MathProgBase.status` (or `status = solve(m)` in JuMP), it is possible to extract the same post-solve variables that are present in AMPL:

- `solve_result`: one of `solved`, `solved?`, `infeasible`, `unbounded`, `limit`, `failure`
- `solve_result_num`: the numeric code returned by the solver. This is solver-specific and gives more granularity than `solve_result`
- `solve_message`: the message printed by the solver at termination
- `solve_exitcode`: the exitcode of the solve process

These can be accessed as follows:

    ampl_model = getInternalModel(m)  # If using JuMP, get a reference to the MathProgBase model
    @show get_solve_result(ampl_model)
    @show get_solve_result_num(ampl_model)
    @show get_solve_message(ampl_model)
    @show get_solve_exitcode(ampl_model)

