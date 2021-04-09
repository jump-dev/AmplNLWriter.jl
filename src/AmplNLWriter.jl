module AmplNLWriter

import MathOptInterface
const MOI = MathOptInterface

MOI.Utilities.@model(
    Optimizer,
    (MOI.ZeroOne, MOI.Integer),
    (MOI.EqualTo, MOI.GreaterThan, MOI.LessThan, MOI.Interval),
    (),
    (),
    (),
    (MOI.ScalarAffineFunction, MOI.ScalarQuadraticFunction),
    (),
    (),
    true,  # So that Model <: MOI.AbstractOptimizer
)

struct _LinearNLPEvaluator <: MOI.AbstractNLPEvaluator end
MOI.initialize(::_LinearNLPEvaluator, ::Vector{Symbol}) = nothing

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
_solver_command(x::String) = f -> f(x)
_solver_command(x::Function) = x

"""
    Optimizer(
        solver_command::Union{String,Function},
        options::Vector{String} = String[],
    )

Create a new Optimizer object.

`solver_command` should be one of two things:

* A `String` of the full path of an AMPL-compatible executable
* A function that takes takes a function as input, initializes any environment
  as needed, calls the input function with a path to the initialized executable,
  and then destructs the environment.

# Examples

A string to an executable:
```julia
Optimizer("/path/to/ipopt.exe", ["print_level=0"])
```

A function or string provided by a package:
```julia
Optimizer(Ipopt.amplexe, ["print_level=0"])
# or
Optimizer(Ipopt_jll.amplexe, ["print_level=0"])
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
"""
function Optimizer(
    solver_command::Union{String,Function} = "",
    options::Vector{String} = String[],
)
    model = Optimizer{Float64}()
    model.ext[:VariablePrimalStart] = Dict{MOI.VariableIndex,Float64}()
    model.ext[:NLPBlock] =
        MOI.NLPBlockData(MOI.NLPBoundsPair[], _LinearNLPEvaluator(), false)
    model.ext[:AMPLSolver] = _solver_command(solver_command)
    model.ext[:Options] = options
    model.ext[:Results] = _NLResults(
        "Optimize not called.",
        MOI.OPTIMIZE_NOT_CALLED,
        MOI.NO_SOLUTION,
        NaN,
        Dict{MOI.VariableIndex,Float64}(),
    )
    return model
end

function MOI.empty!(model::Optimizer{Float64})
    model.name = ""
    model.senseset = false
    model.sense = MOI.FEASIBILITY_SENSE
    model.objectiveset = false
    model.objective =
        MOI.ScalarAffineFunction{Float64}(MOI.ScalarAffineTerm{Float64}[], 0.0)
    model.num_variables_created = 0
    model.variable_indices = nothing
    empty!(model.single_variable_mask)
    empty!(model.lower_bound)
    empty!(model.upper_bound)
    empty!(model.var_to_name)
    model.name_to_var = nothing
    model.nextconstraintid = 0
    empty!(model.con_to_name)
    model.name_to_con = nothing
    empty!(model.constrmap)
    MOI.empty!(model.moi_scalaraffinefunction)
    MOI.empty!(model.moi_scalarquadraticfunction)
    # Reset the extension dictionary.
    model.ext[:VariablePrimalStart] = Dict{MOI.VariableIndex,Float64}()
    model.ext[:NLPBlock] =
        MOI.NLPBlockData(MOI.NLPBoundsPair[], _LinearNLPEvaluator(), false)
    model.ext[:Results] = _NLResults(
        "Optimize not called.",
        MOI.OPTIMIZE_NOT_CALLED,
        MOI.NO_SOLUTION,
        NaN,
        Dict{MOI.VariableIndex,Float64}(),
    )
    return
end

Base.show(io::IO, ::Optimizer) = print(io, "An AMPL (.nl) model")

MOI.get(model::Optimizer, ::MOI.SolverName) = "AmplNLWriter"

# ==============================================================================

MOI.supports(::Optimizer, ::MOI.NLPBlock) = true

function MOI.set(
    model::Optimizer,
    ::MOI.NLPBlock,
    block::Union{Nothing,MOI.NLPBlockData},
)
    model.ext[:NLPBlock] = block
    return
end

MOI.get(model::Optimizer, ::MOI.NLPBlock) = get(model.ext, :NLPBlock, nothing)

# ==============================================================================

function MOI.supports(
    ::Optimizer,
    ::MOI.VariablePrimalStart,
    ::Type{MOI.VariableIndex},
)
    return true
end

function MOI.set(model::Optimizer, ::MOI.VariablePrimalStart, x, v::Real)
    model.ext[:VariablePrimalStart][x] = Float64(v)
    return
end

function MOI.set(model::Optimizer, ::MOI.VariablePrimalStart, x, ::Nothing)
    delete!(model.ext[:VariablePrimalStart], x)
    return
end

function MOI.get(
    model::Optimizer,
    ::MOI.VariablePrimalStart,
    x::MOI.VariableIndex,
)
    return get(model.ext[:VariablePrimalStart], x, nothing)
end

# ==============================================================================

include("NLModel.jl")
include("readsol.jl")

function MOI.optimize!(model::Optimizer)
    options = model.ext[:Options]
    solver = model.ext[:AMPLSolver]
    nlp = _NLModel(model)
    temp_dir = mktempdir()
    nl_file = joinpath(temp_dir, "model.nl")
    open(io -> write(io, nlp), nl_file, "w")
    try
        solver() do solver_path
            ret = run(
                pipeline(
                    `$(solver_path) $(nl_file) -AMPL $(options)`,
                    stdout = stdout,
                    stdin = stdin,
                ),
            )
            if ret.exitcode != 0
                error("Nonzero exit code: $(ret.exitcode)")
            end
        end
        model.ext[:Results] = _read_sol(joinpath(temp_dir, "model.sol"), nlp)
    catch err
        @warn err
        model.ext[:Results] = _NLResults(
            "Error calling the solver. Failed with: $(err)",
            MOI.OTHER_ERROR,
            MOI.NO_SOLUTION,
            NaN,
            Dict{MOI.VariableIndex,Float64}(),
        )
    end
    return
end

_results(model::Optimizer)::_NLResults = model.ext[:Results]

function MOI.get(model::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(model, attr)
    return _results(model).objective_value
end

function MOI.get(
    model::Optimizer,
    attr::MOI.VariablePrimal,
    x::MOI.VariableIndex,
)
    MOI.check_result_index_bounds(model, attr)
    return _results(model).primal_solution[x]
end

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    return _results(model).termination_status
end

function MOI.get(model::Optimizer, attr::MOI.PrimalStatus)
    return attr.N == 1 ? _results(model).primal_status : MOI.NO_SOLUTION
end

MOI.get(::Optimizer, ::MOI.DualStatus) = MOI.NO_SOLUTION

function MOI.get(model::Optimizer, ::MOI.RawStatusString)
    return _results(model).raw_status_string
end

function MOI.get(model::Optimizer, ::MOI.ResultCount)
    return MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT ? 1 : 0
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    idx::MOI.ConstraintIndex,
)
    MOI.check_result_index_bounds(model, attr)
    return MOI.Utilities.get_fallback(model, MOI.ConstraintPrimal(), idx)
end

Base.write(io::IO, model::Optimizer) = write(io, _NLModel(model))

function MOI.write_to_file(model::Optimizer, filename::String)
    open(io -> write(io, model), filename, "w")
    return
end

end
