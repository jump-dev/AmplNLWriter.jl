# AmplNLWriter.jl

[![Build Status](https://github.com/jump-dev/AmplNLWriter.jl/workflows/CI/badge.svg?branch=master)](https://github.com/jump-dev/AmplNLWriter.jl/actions?query=workflow%3ACI)
[![MINLPTests](https://github.com/jump-dev/AmplNLWriter.jl/workflows/MINLPTests/badge.svg?branch=master)](https://github.com/jump-dev/AmplNLWriter.jl/actions?query=workflow%3AMINLPTests)
[![codecov](https://codecov.io/gh/jump-dev/AmplNLWriter.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jump-dev/AmplNLWriter.jl)

[AmplNLWriter.jl](https://github.com/jump-dev/AmplNLWriter.jl) is an interface
between [MathOptInterface.jl](https://github.com/jump-dev/MathOptInterface.jl)
and [AMPL-enabled solvers](http://ampl.com/products/solvers/all-solvers-for-ampl/).

## Affiliation

This wrapper is maintained by the JuMP community and has no official connection
with the AMPL modeling language or AMPL Optimization Inc.

## Installation

Install AmplNLWriter using `Pkg.add`:

```julia
import Pkg
Pkg.add("AmplNLWriter")
```

## Use with JuMP

AmplNLWriter requires an AMPL compatible solver binary to function. Pass a
string pointing to an AMPL-compatible solver binary as the first positional
argument to `AmplNLWriter`. For example, if the `bonmin` executable is on the
system path, use:
```julia
using JuMP, AmplNLWriter
model = Model(() -> AmplNLWriter.Optimizer("bonmin"))
```
If the solver is not on the path, the full path to the solver will need to be
passed in.

## JLL packages

A number of Julia packages provide precompiled binaries that are compatible with
AmplNLWriter. These are generally the name of the solver, followed by `_jll`.
For example, `bomin` is provided by the `Bonmin_jll` package.

To call Bonmin via AmplNLWriter.jl, install the `Bonmin_jll` package, then run:
```julia
using JuMP, AmplNLWriter, Bonmin_jll
model = Model(() -> AmplNLWriter.Optimizer(Bonmin_jll.amplexe))
```

Other packages include:

| Solver | Julia Package | Executable |
| ------ | ------------- | ---------- |
| [Bonmin](https://github.com/coin-or/Bonmin) | `Bonmin_jll` | `Bomin_jll.amplexe` |
| [Couenne](https://github.com/coin-or/Couenne) | `Couenne_jll` | `Couenne_jll.amplexe` |
| [Ipopt](https://github.com/coin-or/Ipopt) | `Ipopt_jll` | `Ipopt_jll.amplexe` |
| [SHOT](https://github.com/coin-or/SHOT) | `SHOT_jll` | `SHOT_jll.amplexe` |

## Supported problem types

List of supported model attributes:

 * `MOI.NLPBlock`
 * `MOI.Name`
 * `MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}`
 * `MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}`
 * `MOI.ObjectiveFunction{MOI.VariableIndex}`
 * `MOI.ObjectiveSense`

List of supported constraint types:

 * `MOI.ScalarAffineFunction{Float64}` in `MOI.EqualTo{Float64}`
 * `MOI.ScalarAffineFunction{Float64}` in `MOI.GreaterThan{Float64}`
 * `MOI.ScalarAffineFunction{Float64}` in `MOI.Interval{Float64}`
 * `MOI.ScalarAffineFunction{Float64}` in `MOI.LessThan{Float64}`
 * `MOI.ScalarQuadraticFunction{Float64}` in `MOI.EqualTo{Float64}`
 * `MOI.ScalarQuadraticFunction{Float64}` in `MOI.GreaterThan{Float64}`
 * `MOI.ScalarQuadraticFunction{Float64}` in `MOI.Interval{Float64}`
 * `MOI.ScalarQuadraticFunction{Float64}` in `MOI.LessThan{Float64}`
 * `MOI.VariableIndex` in `MOI.EqualTo{Float64}`
 * `MOI.VariableIndex` in `MOI.GreaterThan{Float64}`
 * `MOI.VariableIndex` in `MOI.Integer`
 * `MOI.VariableIndex` in `MOI.Interval{Float64}`
 * `MOI.VariableIndex` in `MOI.LessThan{Float64}`
 * `MOI.VariableIndex` in `MOI.ZeroOne`

Note that some solver executables may not support the full list of constraint
types. For example, `Ipopt_jll` does not support `MOI.Integer` or `MOI.ZeroOne`
constraints.

## Options

A list of available options for each solver can be found here:

- [Bonmin](https://github.com/coin-or/Bonmin/blob/master/test/bonmin.opt) (plus Ipopt options)
- [Couenne](https://github.com/coin-or/Couenne/blob/master/src/couenne.opt) (plus Ipopt and Bonmin options)
- [Ipopt](https://coin-or.github.io/Ipopt/OPTIONS.html)
- [SHOT](https://shotsolver.dev/shot/using-shot/solver-options)

Set an option using [`set_attribute`](@ref). For example, to set the
`"bonmin.nlp_log_level"` option to 0 in Bonmin, use:
```julia
using JuMP
import AmplNLWriter
import Bonmin_jll
model = Model(() -> AmplNLWriter.Optimizer(Bonmin_jll.amplexe))
set_attribute(model, "bonmin.nlp_log_level", 0)
```

### opt files

Some of the options need to be specified via an `.opt` file.

This file must be located in the current working directory whenever the model is
solved.

The `.opt` file must be named after the name of the solver, for example,
`bonmin.opt`, and each line must contain an option name and the desired value
separated by a space.

For example, to set the absolute and relative tolerances in Couenne to `1`
and `0.05` respectively, the `couenne.opt` file should contain:
```raw
allowable_gap 1
allowable_fraction_gap 0.05
```
