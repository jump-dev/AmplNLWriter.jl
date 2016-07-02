# AmplNLWriter.jl

Linux, OSX: [![Build Status](https://travis-ci.org/JuliaOpt/AmplNLWriter.jl.svg?branch=master)](https://travis-ci.org/JuliaOpt/AmplNLWriter.jl)

Windows: [![Build Status](https://ci.appveyor.com/api/projects/status/github/JuliaOpt/AmplNLWriter.jl?branch=master&svg=true)](https://ci.appveyor.com/project/jackdunnnz/amplnlwriter-jl/branch/master)


This [Julia](https://github.com/JuliaLang/julia) package is an interface between [MathProgBase.jl](https://github.com/JuliaOpt/MathProgBase.jl) and [AMPL-enabled](http://www.ampl.com) [solvers](http://ampl.com/products/solvers/all-solvers-for-ampl/). It is similar in nature to [CoinOptServices.jl](https://github.com/tkelman/CoinOptServices.jl), but instead uses AMPL's low-level [.nl](https://en.wikipedia.org/wiki/Nl_%28format%29) file format.

A list of AMPL-enabled solvers is available [here](http://ampl.com/products/solvers/all-solvers-for-ampl/).

*Development of AmplNLWriter.jl is community driven and has no official connection with the AMPL modeling language or AMPL Optimization Inc.*

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

The second (optional) argument to ``AmplNLSolver()`` is a ``Vector{ASCIIString}`` of solver options. These options are appended to the solve command separated by spaces, and the required format depends on the solver that you are using. Generally, they will be of the form ``"key=value"``, where ``key`` is the name of the option to set and ``value`` is the desired value. For example, to set the NLP log level to 0 in Bonmin, you would run ``AmplNLSolver("bonmin", ["bonmin.nlp_log_level=0"])``. For a list of options supported by your solver, check the solver's documentation, or run ``/path/to/solver -=`` at the command line e.g. run ``bonmin -=`` for a list of all Bonmin options.

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

## Guides for specific solvers

### Bonmin/Couenne/Ipopt

If you have [CoinOptServices.jl](https://github.com/JuliaOpt/CoinOptServices.jl) installed, you can easily use the Bonmin or Couenne solvers installed by this package:

- Bonmin: ``BonminNLSolver(options)``
- Couenne: ``CouenneNLSolver(options)``

Similarly, if you have [Ipopt.jl](https://github.com/JuliaOpt/Ipopt.jl) installed, you can use Ipopt by using the solver `IpoptNLSolver(options)`.

Bonmin, Couenne and Ipopt all take options in the format ``"key=value"``, and the available options can be seen by running ``/path/to/bonmin -=`` and similarly for the other solvers. For example, the following will turn off the logging in Bonmin for both the NLP and Branch and Bound solvers:

    BonminNLSolver(["bonmin.nlp_log_level=0"; "bonmin.bb_log_level=0"])

Note that some of the options don't seem to take effect when specified using the command-line options (especially for Couenne), and instead you need to use an ``.opt`` file. The ``.opt`` file takes the name of the solver, e.g. ``bonmin.opt``, and each line of this file contains an option name and the desired value separated by a space. For instance, to set the absolute and relative tolerances in Couenne to 1 and 0.05 respectively, the ``couenne.opt`` file should be

```
allowable_gap 1
allowable_fraction_gap 0.05
```

In order for the options to be loaded, this file must be located in the current working directory whenever the model is solved.

A list of available options for the respective ``.opt`` files can be found here:

- [Ipopt](http://www.coin-or.org/Ipopt/documentation/node39.html#app.options_ref)
- [Bonmin](https://github.com/coin-or/Bonmin/blob/master/Bonmin/test/bonmin.opt) (plus Ipopt options)
- [Couenne](https://github.com/coin-or/Couenne/blob/master/Couenne/src/couenne.opt) (plus Ipopt and Bonmin options)

### SCIP

To use SCIP with AmplNLWriter.jl, you must first compile the ``scipampl`` binary which is a version of SCIP with support for the AMPL .nl interface. To do this, you can follow the instructions [here](http://zverovich.net/2012/08/07/using-scip-with-ampl.html), which we have tested on OS X and Linux.

After doing this, you can access SCIP through ``AmplNLSolver("/path/to/scipampl")``. Options can be specified for SCIP using a ``scip.set`` file, where each line is of the form ``key = value``. For example, the following `scip.set` file will set the verbosity level to 0:

    display/verblevel = 0

A list of valid options for the file can be found [here](http://plato.asu.edu/milp/scip.set).

To use the ``scip.set`` file, you must pass the path to the ``scip.set`` file as the first (and only) option to the solver:

    AmplNLSolver("/path/to/scipampl", ["/path/to/scip.set"])
