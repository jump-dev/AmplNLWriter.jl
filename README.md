# AmplNLWriter.jl

[![Build Status](https://github.com/jump-dev/AmplNLWriter.jl/workflows/CI/badge.svg?branch=master)](https://github.com/jump-dev/AmplNLWriter.jl/actions?query=workflow%3ACI)
[![MINLPTests](https://github.com/jump-dev/AmplNLWriter.jl/workflows/MINLPTests/badge.svg?branch=master)](https://github.com/jump-dev/AmplNLWriter.jl/actions?query=workflow%3AMINLPTests)
[![codecov](https://codecov.io/gh/jump-dev/AmplNLWriter.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jump-dev/AmplNLWriter.jl)

AmplNLWriter.jl is an interface between [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl)
and [AMPL-enabled solvers](http://ampl.com/products/solvers/all-solvers-for-ampl/).

*Note: this wrapper is maintained by the JuMP community and has no official
connection with the AMPL modeling language or AMPL Optimization Inc.*

## Installation

Install AmplNLWriter using `Pkg.add`.

```julia
import Pkg
Pkg.add("AmplNLWriter")
```

**Note: AmplNLWriter requires Julia 1.6 or later.**

### Solvers

You also need an AMPL compatible solver.

#### Bonmin (https://github.com/coin-or/Bonmin)

To install Bonmin, use:
```julia
Pkg.add("Bonmin_jll")
```

#### Couenne (https://github.com/coin-or/Couenne)

To install Couenne, use:
```julia
Pkg.add("Couenne_jll")
```

#### Ipopt (https://github.com/coin-or/Ipopt)

To install Ipopt, use:
```julia
Pkg.add("Ipopt_jll")
```

#### SHOT (https://github.com/coin-or/SHOT)

To install SHOT, use:
```julia
Pkg.add("SHOT_jll")
```

## Usage

### JLL packages

To call Bonmin via AmplNLWriter.jl, use:
```julia
using JuMP, AmplNLWriter, Bonmin_jll
model = Model(() -> AmplNLWriter.Optimizer(Bonmin_jll.amplexe))

# or equivalently

model = Model() do
    AmplNLWriter.Optimizer(Bonmin_jll.amplexe)
end
```

Replace `Bonmin_jll` with `Couenne_jll`, `Ipopt_jll`, or `SHOT_jll` as appropriate.

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

A list of available options for each solver can be found here:

- [Bonmin](https://github.com/coin-or/Bonmin/blob/master/test/bonmin.opt) (plus Ipopt options)
- [Couenne](https://github.com/coin-or/Couenne/blob/master/src/couenne.opt) (plus Ipopt and Bonmin options)
- [Ipopt](https://coin-or.github.io/Ipopt/OPTIONS.html)
- [SHOT](https://shotsolver.dev/shot/using-shot/solver-options)

Set an option using `set_optimizer_attribute`. For example, to set the
`"bonmin.nlp_log_level"` option to 0 in Bonmin, use:
```julia
using JuMP, AmplNLWriter, Bonmin_jll
model = Model(() -> AmplNLWriter.Optimizer(Bonmin_jll.amplexe))
set_optimizer_attribute(model, "bonmin.nlp_log_level", 0)
```

### opt files

Some of the options need to be specified via an `.opt` file. This file must be
located in the current working directory whenever the model is solved.

The `.opt` file must be named after the name of the solver, e.g. `bonmin.opt`, and
each line must contain an option name and the desired value separated by a space.
For instance, to set the absolute and relative tolerances in Couenne to 1 and
0.05 respectively, the `couenne.opt` is:
```
allowable_gap 1
allowable_fraction_gap 0.05
```
