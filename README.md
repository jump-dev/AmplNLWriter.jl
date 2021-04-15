# AmplNLWriter.jl

AmplNLWriter.jl is an interface between [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl)
and [AMPL-enabled solvers](http://ampl.com/products/solvers/all-solvers-for-ampl/).

*Development of AmplNLWriter.jl is community driven and has no official
connection with the AMPL modeling language or AMPL Optimization Inc.*

[![Build Status](https://github.com/jump-dev/AmplNLWriter.jl/workflows/CI/badge.svg?branch=master)](https://github.com/jump-dev/AmplNLWriter.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/jump-dev/AmplNLWriter.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jump-dev/AmplNLWriter.jl)

## Installation

The package can be installed with `Pkg.add`.

```julia
import Pkg
Pkg.add("AmplNLWriter")
```

### Solvers

You also need an AMPL compatible solver.

**Note: the `_jll` packages require Julia 1.3 or later.**

#### Bonmin

To install Bonmin, use:
```julia
Pkg.add("Bonmin_jll")
```

#### Couenne

To install Couenne, use:
```julia
Pkg.add("Couenne_jll")
```

#### Ipopt

To install Ipopt, use:
```julia
Pkg.add("Ipopt_jll")
```

## Usage

### JLL packages

To call Ipopt via AmplNLWriter.jl, use:
```julia
using JuMP, AmplNLWriter, Ipopt_jll
model = Model(() -> AmplNLWriter.Optimizer(Ipopt_jll.amplexe))

# or equivalently

model = Model() do
    AmplNLWriter.Optimizer(Ipopt_jll.amplexe)
end
```

Replace `Ipopt_jll` with `Bonmin_jll` or `Couenne_jll` as appropriate.

### Other binaries

You can also pass a string pointing to an AMPL-compatible solver executable. For
example, if the `bonmin` executable is on the system path, use:
```julia
using JuMP, AmplNLWriter
model = Model(() -> AmplNLWriter.Optimizer("bonmin"))
```

If the solver is not on the path, the full path to the solver will need to be
passed in.

## Options

Options are appended to the solve command separated by spaces, and the required 
format depends on the solver that you are using. Generally, they will be of the 
form `"key=value"`, where `key` is the name of the option to set and `value` is 
the desired value.

For example, to set the `"bonmin.nlp_log_level"` option to 0 in Bonmin, use:
```julia
model = AmplNLWriter.Optimizer(Bonmin_jll.amplexe)
MOI.set(model, MOI.RawParameter("bonmin.nlp_log_level"), 0)
```

For a list of options supported by your solver, check the solver's
documentation, or run `/path/to/solver -=` at the command line. For `_jll` 
packages, use:
```julia
Bonmin_jll.amplexe() do path
   run(`$(path) -=`)
 end
```

Note that some of the options don't seem to take effect when specified using the
command-line options (especially for Couenne), and instead you need to use an
`.opt` file.

The `.opt` file takes the name of the solver, e.g. `bonmin.opt`, and each line
of this file contains an option name and the desired value separated by a space.
For instance, to set the absolute and relative tolerances in Couenne to 1 and
0.05 respectively, the `couenne.opt` file should be
```
allowable_gap 1
allowable_fraction_gap 0.05
```

In order for the options to be loaded, this file must be located in the current
working directory whenever the model is solved.

A list of available options for the respective `.opt` files can be found here:

- [Ipopt](https://coin-or.github.io/Ipopt/OPTIONS.html)
- [Bonmin](https://github.com/coin-or/Bonmin/blob/master/test/bonmin.opt) (plus Ipopt options)
- [Couenne](https://github.com/coin-or/Couenne/blob/master/src/couenne.opt) (plus Ipopt and Bonmin options)
