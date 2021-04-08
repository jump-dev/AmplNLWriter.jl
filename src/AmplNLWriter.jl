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

function Base.show(io::IO, ::Optimizer)
    print(io, "An AMPL (.NL) model")
    return
end

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
    println(read(nl_file, String))
    try
        solver() do solver_path
            return run(
                pipeline(
                    `$(solver_path) $(nl_file) -AMPL $(options)`,
                    stdout = stdout,
                    stdin = stdin,
                ),
            )
        end
        open(joinpath(temp_dir, "model.sol"), "r") do sol_io
            return model.ext[:Results] = _read_sol(sol_io, nlp)
        end
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

function MOI.get(model::Optimizer, ::MOI.ObjectiveValue)
    return _results(model).objective_value
end

function MOI.get(model::Optimizer, ::MOI.VariablePrimal, x::MOI.VariableIndex)
    return _results(model).primal_solution[x]
end

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    return _results(model).termination_status
end

function MOI.get(model::Optimizer, ::MOI.PrimalStatus)
    return _results(model).primal_status
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
    ::MOI.ConstraintPrimal,
    idx::MOI.ConstraintIndex,
)
    return MOI.Utilities.get_fallback(model, MOI.ConstraintPrimal(), idx)
end

Base.write(io::IO, model::Optimizer) = write(io, _NLModel(model))

function MOI.write_to_file(model::Optimizer, filename::String)
    open(io -> write(io, model), filename, "w")
    return
end

end
