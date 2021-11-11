module AmplNLWriter

import MathOptInterface
const MOI = MathOptInterface

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
end

function call_solver(
    solver::_DefaultSolverCommand,
    nl_filename::String,
    options::Vector{String},
    stdin::IO,
    stdout::IO,
)
    solver.f() do solver_path
        ret = run(
            pipeline(
                `$(solver_path) $(nl_filename) -AMPL $(options)`,
                stdin = stdin,
                stdout = stdout,
            ),
        )
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
_solver_command(x::String) = _DefaultSolverCommand(f -> f(x))
_solver_command(x::Function) = _DefaultSolverCommand(x)
_solver_command(x::AbstractSolverCommand) = x

struct _NLResults
    raw_status_string::String
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    objective_value::Float64
    primal_solution::Dict{MOI.VariableIndex,Float64}
    dual_solution::Vector{Float64}
    zL_out::Dict{MOI.VariableIndex,Float64}
    zU_out::Dict{MOI.VariableIndex,Float64}
end

mutable struct Optimizer <: MOI.AbstractOptimizer
    inner::MOI.FileFormats.NL.Model
    solver_command::AbstractSolverCommand
    options::Dict{String,Any}
    stdin::Any
    stdout::Any
    results::_NLResults
    solve_time::Float64
end

"""
    Optimizer(
        solver_command::Union{String,Function},
        solver_args::Vector{String};
        stdin::Any = stdin,
        stdout:Any = stdout,
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
)
    return Optimizer(
        MOI.FileFormats.NL.Model(),
        _solver_command(solver_command),
        Dict{String,String}(opt => "" for opt in solver_args),
        stdin,
        stdout,
        _NLResults(
            "Optimize not called.",
            MOI.OPTIMIZE_NOT_CALLED,
            MOI.NO_SOLUTION,
            NaN,
            Dict{MOI.VariableIndex,Float64}(),
            Float64[],
            Dict{MOI.VariableIndex,Float64}(),
            Dict{MOI.VariableIndex,Float64}(),
        ),
        NaN,
    )
end

Base.show(io::IO, ::Optimizer) = print(io, "An AMPL (.nl) model")

function MOI.empty!(model::Optimizer)
    MOI.empty!(model.inner)
    model.results = _NLResults(
        "Optimize not called.",
        MOI.OPTIMIZE_NOT_CALLED,
        MOI.NO_SOLUTION,
        NaN,
        Dict{MOI.VariableIndex,Float64}(),
        Float64[],
        Dict{MOI.VariableIndex,Float64}(),
        Dict{MOI.VariableIndex,Float64}(),
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

MOI.supports_incremental_interface(::Optimizer) = false

MOI.copy_to(dest::Optimizer, src::MOI.ModelLike) = MOI.copy_to(dest.inner, src)

function MOI.supports(
    ::Optimizer,
    ::MOI.VariablePrimalStart,
    ::Type{MOI.VariableIndex},
)
    return true
end

function MOI.set(model::Optimizer, ::MOI.VariablePrimalStart, x, v::Real)
    model.inner.x[x].start = Float64(v)
    return
end

function MOI.set(model::Optimizer, ::MOI.VariablePrimalStart, x, ::Nothing)
    model.inner.x[x].start = nothing
    return
end

function MOI.get(
    model::Optimizer,
    ::MOI.VariablePrimalStart,
    x::MOI.VariableIndex,
)
    return model.inner.x[x].start
end

"""
    _interpret_status(solve_result_num::Int, raw_status_string::String)

Convert the `solve_result_num` and `raw_status_string` into MOI-type statuses.

For the primal status, assume a solution is present. Other code is responsible
for returning `MOI.NO_SOLUTION` if no primal solution is present.
"""
function _interpret_status(solve_result_num::Int, raw_status_string::String)
    if 0 <= solve_result_num < 100
        # Solved, and nothing went wrong. Even though we say `LOCALLY_SOLVED`,
        # some solvers like SHOT use this status to represent problems that are
        # provably globally optimal.
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT
    elseif 100 <= solve_result_num < 200
        # Solved, but the solver can't be sure for some reason. e.g., SHOT
        # uses this for non-convex problems it isn't sure is the global optima.
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT
    elseif 200 <= solve_result_num < 300
        return MOI.INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif 300 <= solve_result_num < 400
        return MOI.DUAL_INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif 400 <= solve_result_num < 500
        return MOI.OTHER_LIMIT, MOI.UNKNOWN_RESULT_STATUS
    elseif 500 <= solve_result_num < 600
        return MOI.OTHER_ERROR, MOI.UNKNOWN_RESULT_STATUS
    end
    # If we didn't get a valid solve_result_num, try to get the status from the
    # solve_message string. Some solvers (e.g. SCIP) don't ever print the
    # suffixes so we need this.
    message = lowercase(raw_status_string)
    if occursin("optimal", message)
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT
    elseif occursin("infeasible", message)
        return MOI.INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif occursin("unbounded", message)
        return MOI.DUAL_INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif occursin("limit", message)
        return MOI.OTHER_LIMIT, MOI.UNKNOWN_RESULT_STATUS
    elseif occursin("error", message)
        return MOI.OTHER_ERROR, MOI.UNKNOWN_RESULT_STATUS
    else
        return MOI.OTHER_ERROR, MOI.UNKNOWN_RESULT_STATUS
    end
end

function _readline(io::IO)
    if eof(io)
        error("Reached end of sol file unexpectedly.")
    end
    return strip(readline(io))
end
_readline(io::IO, T) = parse(T, _readline(io))

function _read_sol(filename::String, model::MOI.FileFormats.NL.Model)
    return open(io -> _read_sol(io, model), filename, "r")
end

"""
    _read_sol(io::IO, model::MOI.FileFormats.NL.Model)

This function is based on a Julia translation of readsol.c, available at
https://github.com/ampl/asl/blob/64919f75fa7a438f4b41bce892dcbe2ae38343ee/src/solvers/readsol.c
and under the following license:

Copyright (C) 2017 AMPL Optimization, Inc.; written by David M. Gay.
Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted,
provided that the above copyright notice appear in all copies and that
both that the copyright notice and this permission notice and warranty
disclaimer appear in supporting documentation.

The author and AMPL Optimization, Inc. disclaim all warranties with
regard to this software, including all implied warranties of
merchantability and fitness.  In no event shall the author be liable
for any special, indirect or consequential damages or any damages
whatsoever resulting from loss of use, data or profits, whether in an
action of contract, negligence or other tortious action, arising out
of or in connection with the use or performance of this software.
"""
function _read_sol(io::IO, model::MOI.FileFormats.NL.Model)
    raw_status_string = ""
    line = ""
    while !startswith(line, "Options")
        line = _readline(io)
        raw_status_string *= line
    end
    # Read through all the options. Direct copy of reference implementation.
    @assert startswith(line, "Options")
    num_options = _readline(io, Int)
    need_vbtol = false
    if num_options > 0
        if !(3 <= num_options <= 9)
            error("expected num_options between 3 and 9; " * "got $num_options")
        end
        _readline(io, Int)  # Skip this line
        if _readline(io, Int) == 3
            num_options -= 2
            need_vbtol = true
        end
        for _ in 3:num_options
            _readline(io, Int)  # Skip the rest of the option lines
        end
    end
    # Read number of constraints
    num_cons = _readline(io, Int)
    @assert(num_cons == length(model.g) + length(model.h))
    # Read number of dual solutions to read in
    num_duals_to_read = _readline(io, Int)
    @assert(num_duals_to_read == 0 || num_duals_to_read == num_cons)
    # Read number of variables
    num_vars = _readline(io, Int)
    @assert(num_vars == length(model.x))
    # Read number of primal solutions to read in
    num_vars_to_read = _readline(io, Int)
    @assert(num_vars_to_read == 0 || num_vars_to_read == num_vars)
    # Skip over vbtol line if present
    if need_vbtol
        _readline(io)
    end
    # Read dual solutions
    dual_solution = Float64[_readline(io, Float64) for i in 1:num_duals_to_read]
    # Read primal solutions
    primal_solution = Dict{MOI.VariableIndex,Float64}()
    if num_vars_to_read > 0
        for xi in model.order
            primal_solution[xi] = _readline(io, Float64)
        end
    end
    # Check for status code
    solve_result_num = -1
    while !eof(io)
        linevals = split(_readline(io), " ")
        if length(linevals) > 0 && linevals[1] == "objno"
            @assert parse(Int, linevals[2]) == 0
            solve_result_num = parse(Int, linevals[3])
            break
        end
    end
    zL_out = Dict{MOI.VariableIndex,Float64}()
    zU_out = Dict{MOI.VariableIndex,Float64}()
    while !eof(io)
        line = _readline(io)
        if startswith(line, "suffix")
            items = split(line, " ")
            n_suffix = parse(Int, items[3])
            suffix = _readline(io)
            if !(suffix == "ipopt_zU_out" || suffix == "ipopt_zL_out")
                continue
            end
            for i in 1:n_suffix
                items = split(_readline(io), " ")
                x = model.order[parse(Int, items[1])+1]
                dual = parse(Float64, items[2])
                if suffix == "ipopt_zU_out"
                    zU_out[x] = dual
                else
                    @assert suffix == "ipopt_zL_out"
                    zL_out[x] = dual
                end
            end
        end
    end
    termination_status, primal_status =
        _interpret_status(solve_result_num, raw_status_string)
    objective_value = NaN
    if length(primal_solution) > 0
        # .sol files don't seem to be able to return the objective
        # value. Evaluate it here instead.
        objective_value = MOI.FileFormats.NL._evaluate(model.f, primal_solution)
    end
    return _NLResults(
        raw_status_string,
        termination_status,
        length(primal_solution) > 0 ? primal_status : MOI.NO_SOLUTION,
        objective_value,
        primal_solution,
        dual_solution,
        zL_out,
        zU_out,
    )
end

function MOI.optimize!(model::Optimizer)
    start_time = time()
    temp_dir = mktempdir()
    nl_file = joinpath(temp_dir, "model.nl")
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
        model.results = _read_sol(sol_file, model.inner)
    catch err
        model.results = _NLResults(
            "Error calling the solver. Failed with: $(err)",
            MOI.OTHER_ERROR,
            MOI.NO_SOLUTION,
            NaN,
            Dict{MOI.VariableIndex,Float64}(),
            Float64[],
            Dict{MOI.VariableIndex,Float64}(),
            Dict{MOI.VariableIndex,Float64}(),
        )
    end
    model.solve_time = time() - start_time
    return
end

function MOI.get(model::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(model, attr)
    return model.results.objective_value
end

function MOI.get(
    model::Optimizer,
    attr::MOI.VariablePrimal,
    x::MOI.VariableIndex,
)
    MOI.check_result_index_bounds(model, attr)
    return model.results.primal_solution[x]
end

MOI.get(model::Optimizer, ::MOI.SolveTimeSec) = model.solve_time

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    return model.results.termination_status
end

function MOI.get(model::Optimizer, attr::MOI.PrimalStatus)
    if attr.result_index != 1
        return MOI.NO_SOLUTION
    end
    return model.results.primal_status
end

function MOI.get(model::Optimizer, attr::MOI.DualStatus)
    n_duals =
        length(model.results.dual_solution) +
        length(model.results.zL_out) +
        length(model.results.zU_out)
    if attr.result_index != 1 ||
       n_duals == 0 ||
       model.results.termination_status != MOI.LOCALLY_SOLVED
        return MOI.NO_SOLUTION
    end
    return MOI.FEASIBLE_POINT
end

function MOI.get(model::Optimizer, ::MOI.RawStatusString)
    return model.results.raw_status_string
end

function MOI.get(model::Optimizer, ::MOI.ResultCount)
    return MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT ? 1 : 0
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{<:MOI.VariableIndex},
)
    MOI.check_result_index_bounds(model, attr)
    return model.results.primal_solution[MOI.VariableIndex(ci.value)]
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{<:MOI.ScalarAffineFunction},
)
    MOI.check_result_index_bounds(model, attr)
    return MOI.FileFormats.NL._evaluate(
        model.inner.h[ci.value].expr,
        model.results.primal_solution,
    )
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{<:MOI.ScalarQuadraticFunction},
)
    MOI.check_result_index_bounds(model, attr)
    return MOI.FileFormats.NL._evaluate(
        model.inner.g[ci.value].expr,
        model.results.primal_solution,
    )
end

function MOI.get(model::Optimizer, attr::MOI.DualObjectiveValue)
    MOI.check_result_index_bounds(model, attr)
    # TODO(odow): replace this with the proper dual objective.
    return MOI.get(model, MOI.ObjectiveValue())
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    dual = get(model.results.zU_out, MOI.VariableIndex(ci.value), 0.0)
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    dual = get(model.results.zL_out, MOI.VariableIndex(ci.value), 0.0)
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    x = MOI.VariableIndex(ci.value)
    dual = get(model.results.zL_out, x, 0.0) + get(model.results.zU_out, x, 0.0)
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.Interval{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    x = MOI.VariableIndex(ci.value)
    dual = get(model.results.zL_out, x, 0.0) + get(model.results.zU_out, x, 0.0)
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{<:MOI.ScalarAffineFunction},
)
    MOI.check_result_index_bounds(model, attr)
    dual = model.results.dual_solution[length(model.inner.g)+ci.value]
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{<:MOI.ScalarQuadraticFunction},
)
    MOI.check_result_index_bounds(model, attr)
    dual = model.results.dual_solution[ci.value]
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

function MOI.get(model::Optimizer, attr::MOI.NLPBlockDual)
    MOI.check_result_index_bounds(model, attr)
    dual = model.results.dual_solution[1:model.inner.nlpblock_dim]
    return model.inner.sense == MOI.MIN_SENSE ? dual : -dual
end

end
