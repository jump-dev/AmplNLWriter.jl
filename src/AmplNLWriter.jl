# Copyright (c) 2015: AmplNLWriter.jl contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module AmplNLWriter

import LinearAlgebra
import MathOptInterface as MOI
import OpenBLAS32_jll

function __init__()
    if VERSION >= v"1.8"
        config = LinearAlgebra.BLAS.lbt_get_config()
        if !any(lib -> lib.interface == :lp64, config.loaded_libs)
            LinearAlgebra.BLAS.lbt_forward(OpenBLAS32_jll.libopenblas_path)
        end
    end
    return
end

function _get_blas_loaded_libs()
    if VERSION >= v"1.8"
        config = LinearAlgebra.BLAS.lbt_get_config()
        return join([lib.libname for lib in config.loaded_libs], ";")
    end
    return ""
end

"""
    AbstractSolverCommand

An abstract type that allows over-riding the call behavior of the solver.

See also: [`call_solver`](@ref).
"""
abstract type AbstractSolverCommand end

"""
    call_solver(
        solver::AbstractSolverCommand,
        nl_filename::String,
        options::Vector{String},
        stdin::IO,
        stdout::IO,
    )::String

Execute the `solver` given the NL file at `nl_filename`, a vector of `options`,
and `stdin` and `stdout`. Return the filename of the resulting `.sol` file.

You can assume `nl_filename` ends in `model.nl`, and that you can write a `.sol`
file to `replace(nl_filename, "model.nl" => "model.sol")`.

If anything goes wrong, throw a descriptive error.
"""
function call_solver end

struct _DefaultSolverCommand{F} <: AbstractSolverCommand
    f::F
    flags::Vector{String}
end

function call_solver(
    solver::_DefaultSolverCommand,
    nl_filename::String,
    options::Vector{String},
    stdin::IO,
    stdout::IO,
)
    solver.f() do solver_path
        # Solvers like Ipopt_jll use libblastrampoline. That requires us to set
        # the BLAS library via the LBT_DEFAULT_LIBS environment variable.
        # Provide a default in case the user doesn't set.
        lbt_default_libs = get(ENV, "LBT_DEFAULT_LIBS", _get_blas_loaded_libs())
        cmd = `$solver_path $nl_filename $(solver.flags) $options`
        if !isempty(lbt_default_libs)
            cmd = addenv(cmd, "LBT_DEFAULT_LIBS" => lbt_default_libs)
        end
        ret = run(pipeline(cmd; stdin = stdin, stdout = stdout))
        if ret.exitcode != 0
            error("Nonzero exit code: $(ret.exitcode)")
        end
    end
    return replace(nl_filename, "model.nl" => "model.sol")
end

"""
    _solver_command(x::Union{Function,String})

Functionify the solver command so it can be called as follows:
```julia
foo = _solver_command(x)
foo() do path
    run(`\$(path) args...`)
end
```
"""
_solver_command(x::String, flags) = _DefaultSolverCommand(f -> f(x), flags)
_solver_command(x::Function, flags) = _DefaultSolverCommand(x, flags)
_solver_command(x::AbstractSolverCommand, flags) = x

mutable struct Optimizer <: MOI.AbstractOptimizer
    inner::MOI.FileFormats.NL.Model
    solver_command::AbstractSolverCommand
    options::Dict{String,Any}
    stdin::Any
    stdout::Any
    directory::String
    results::MOI.FileFormats.NL.SolFileResults
    solve_time::Float64
end

"""
    Optimizer(
        solver_command::Union{String,Function},
        solver_args::Vector{String};
        stdin::Any = stdin,
        stdout:Any = stdout,
        directory::String = "",
    )

Create a new Optimizer object.

## Arguments

 * `solver_command`: one of two things:
   * A `String` of the full path of an AMPL-compatible executable
   * A function that takes takes a function as input, initializes any
     environment as needed, calls the input function with a path to the
     initialized executable, and then destructs the environment.
 * `solver_args`: a vector of `String` arguments passed solver executable.
   However, prefer passing `key=value` options via `MOI.RawOptimizerAttribute`.
 * `stdin` and `stdio`: arguments passed to `Base.pipeline` to redirect IO. See
   the Julia documentation for more details by typing `? pipeline` at the Julia
   REPL.
 * `directory`: the directory in which to write the `model.nl` and `model.sol`
   files. If left empty, this defaults to a temporary directory. This argument
   may be useful when debugging.

## Examples

A string to an executable:
```julia
Optimizer("/path/to/ipopt.exe")
```

A function or string provided by a package:
```julia
Optimizer(Ipopt.amplexe)
# or
Optimizer(Ipopt_jll.amplexe)
```

A custom function
```julia
function solver_command(f::Function)
    # Create environment ...
    ret = f("/path/to/ipopt")
    # Destruct environment ...
    return ret
end
Optimizer(solver_command)
```

The following two calls are equivalent:
```julia
# Okay:
model = Optimizer(Ipopt_jll.amplexe, ["print_level=0"])
# Better:
model = Optimizer(Ipopt_jll.amplexe)
MOI.set(model, MOI.RawOptimizerAttribute("print_level"), 0
```
"""
function Optimizer(
    solver_command::Union{AbstractSolverCommand,String,Function} = "",
    solver_args::Vector{String} = String[];
    stdin::Any = stdin,
    stdout::Any = stdout,
    directory::String = "",
    flags::Vector{String} = ["-AMPL"],
)
    return Optimizer(
        MOI.FileFormats.NL.Model(),
        _solver_command(solver_command, flags),
        Dict{String,String}(opt => "" for opt in solver_args),
        stdin,
        stdout,
        directory,
        MOI.FileFormats.NL.SolFileResults(
            "Optimize not called.",
            MOI.OPTIMIZE_NOT_CALLED,
        ),
        NaN,
    )
end

Base.show(io::IO, ::Optimizer) = print(io, "An AMPL (.nl) model")

function MOI.empty!(model::Optimizer)
    MOI.empty!(model.inner)
    model.results = MOI.FileFormats.NL.SolFileResults(
        "Optimize not called.",
        MOI.OPTIMIZE_NOT_CALLED,
    )
    model.solve_time = NaN
    return
end

MOI.is_empty(model::Optimizer) = MOI.is_empty(model.inner)

MOI.get(model::Optimizer, ::MOI.SolverName) = "AmplNLWriter"

MOI.supports(::Optimizer, ::MOI.Name) = true

MOI.get(model::Optimizer, ::MOI.Name) = MOI.get(model.inner, MOI.Name())

function MOI.set(model::Optimizer, ::MOI.Name, name::String)
    MOI.set(model.inner, MOI.Name(), name)
    return
end

MOI.supports(::Optimizer, ::MOI.RawOptimizerAttribute) = true

function MOI.get(model::Optimizer, attr::MOI.RawOptimizerAttribute)
    return get(model.options, attr.name, nothing)
end

function MOI.set(model::Optimizer, attr::MOI.RawOptimizerAttribute, value)
    model.options[attr.name] = value
    return
end

const _SCALAR_FUNCTIONS = Union{
    MOI.VariableIndex,
    MOI.ScalarAffineFunction{Float64},
    MOI.ScalarQuadraticFunction{Float64},
    MOI.ScalarNonlinearFunction,
}

const _SCALAR_SETS = Union{
    MOI.LessThan{Float64},
    MOI.GreaterThan{Float64},
    MOI.EqualTo{Float64},
    MOI.Interval{Float64},
}

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:_SCALAR_FUNCTIONS},
    ::Type{<:_SCALAR_SETS},
)
    return true
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VariableIndex},
    ::Type{<:Union{MOI.ZeroOne,MOI.Integer}},
)
    return true
end

MOI.supports(::Optimizer, ::MOI.ObjectiveFunction{<:_SCALAR_FUNCTIONS}) = true

MOI.supports(::Optimizer, ::MOI.ObjectiveSense) = true

MOI.supports(::Optimizer, ::MOI.NLPBlock) = true

function MOI.supports(
    ::Optimizer,
    ::MOI.VariablePrimalStart,
    ::Type{MOI.VariableIndex},
)
    return true
end

MOI.supports_incremental_interface(::Optimizer) = false

MOI.copy_to(dest::Optimizer, src::MOI.ModelLike) = MOI.copy_to(dest.inner, src)

function MOI.optimize!(model::Optimizer)
    start_time = time()
    directory = model.directory
    if isempty(model.directory)
        directory = mktempdir()
    end
    nl_file = joinpath(directory, "model.nl")
    open(io -> write(io, model.inner), nl_file, "w")
    options = String[isempty(v) ? k : "$(k)=$(v)" for (k, v) in model.options]
    try
        sol_file = call_solver(
            model.solver_command,
            nl_file,
            options,
            model.stdin,
            model.stdout,
        )
        if isfile(sol_file)
            model.results =
                MOI.FileFormats.NL.SolFileResults(sol_file, model.inner)
        else
            model.results = MOI.FileFormats.NL.SolFileResults(
                "Error calling the solver. The solver executed normally, but " *
                "no `.sol` file was created. This usually means that there " *
                "is an issue with the formulation of your model. Check the " *
                "solver's logs for details.",
                MOI.OTHER_ERROR,
            )
        end
    catch err
        model.results = MOI.FileFormats.NL.SolFileResults(
            "Error calling the solver. Failed with: $(err)",
            MOI.OTHER_ERROR,
        )
    end
    model.solve_time = time() - start_time
    return
end

MOI.get(model::Optimizer, ::MOI.SolveTimeSec) = model.solve_time

function MOI.get(
    model::Optimizer,
    attr::Union{
        MOI.ResultCount,
        MOI.RawStatusString,
        MOI.TerminationStatus,
        MOI.PrimalStatus,
        MOI.DualStatus,
        MOI.ObjectiveValue,
        MOI.NLPBlockDual,
    },
)
    return MOI.get(model.results, attr)
end

function MOI.get(
    model::Optimizer,
    attr::MOI.VariablePrimal,
    x::MOI.VariableIndex,
)
    return MOI.get(model.results, attr, x)
end

function MOI.get(
    model::Optimizer,
    attr::Union{MOI.ConstraintPrimal,MOI.ConstraintDual},
    ci::MOI.ConstraintIndex,
)
    return MOI.get(model.results, attr, ci)
end

function MOI.get(model::Optimizer, attr::MOI.DualObjectiveValue)
    MOI.check_result_index_bounds(model, attr)
    # TODO(odow): replace this with the proper dual objective.
    return MOI.get(model, MOI.ObjectiveValue())
end

end
