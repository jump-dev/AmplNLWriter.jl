using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities

import MathProgBase
const MPB = MathProgBase.SolverInterface

MOIU.@model(InnerModel,
    (MOI.ZeroOne, MOI.Integer),
    (MOI.EqualTo, MOI.GreaterThan, MOI.LessThan, MOI.Interval),
    (),
    (),
    (MOI.SingleVariable,),
    (MOI.ScalarAffineFunction, MOI.ScalarQuadraticFunction),
    (),
    ()
)

const MOI_SCALAR_SETS = (
    MOI.EqualTo{Float64}, MOI.GreaterThan{Float64}, MOI.LessThan{Float64},
    MOI.Interval{Float64}
)

# Make `Model` a constant for use in the rest of the file.
const Model = MOIU.UniversalFallback{InnerModel{Float64}}

# Only support the constraint types defined by `InnerModel`.
function MOI.supports_constraint(
        model::Model, F::Type{<:MOI.AbstractFunction}, S::Type{MOI.AbstractSet})
    return MOI.supports_constraint(model.model, F, S)
end

"Attribute for the MathProgBase solver."
struct MPBSolver <: MOI.AbstractOptimizerAttribute end

"Attribute for the MathProgBase status."
struct MPBSolutionAttribute <: MOI.AbstractModelAttribute end

"Struct to contain the MPB solution."
struct MPBSolution
    status::Symbol
    is_minimization::Bool
    objective_value::Float64
    primal_solution::Dict{MOI.VariableIndex, Float64}
end

"""
    Optimizer(
        solver_command::String,
        options::Vector{String} = String[];
        filename::String = ""
    )

# Example

    Optimizer(Ipopt.amplexe, ["print_level=0"])
"""
function Optimizer(
    solver_command::String,
    options::Vector{String} = String[];
    filename::String = "")
    model = MOIU.UniversalFallback(InnerModel{Float64}())
    MOI.set(model, MPBSolver(),
        AmplNLSolver(solver_command, options, filename = filename)
    )
    return model
end

Base.show(io::IO, ::Model) = println(io, "A MathProgBase model")

# We re-define is_empty and empty! to prevent the universal fallback from
# deleting the solver that we are caching in it.
function MOI.is_empty(model::Model)
    return MOI.is_empty(model.model) &&
        isempty(model.constraints) &&
        isempty(model.modattr) &&
        isempty(model.varattr) &&
        isempty(model.conattr) &&
        length(model.optattr) == 1 &&
        haskey(model.optattr, MPBSolver())
end

function MOI.empty!(model::Model)
    MOI.empty!(model.model)
    empty!(model.constraints)
    model.nextconstraintid = 0
    empty!(model.con_to_name)
    model.name_to_con = nothing
    empty!(model.modattr)
    empty!(model.varattr)
    empty!(model.conattr)
    mpb_solver = model.optattr[MPBSolver()]
    empty!(model.optattr)
    model.optattr[MPBSolver()] = mpb_solver
    return
end

set_to_bounds(set::MOI.LessThan) = (-Inf, set.upper)
set_to_bounds(set::MOI.GreaterThan) = (set.lower, Inf)
set_to_bounds(set::MOI.EqualTo) = (set.value, set.value)
set_to_bounds(set::MOI.Interval) = (set.lower, set.upper)
set_to_cat(set::MOI.ZeroOne) = :Bin
set_to_cat(set::MOI.Integer) = :Int

struct NLPEvaluator{T <: MOI.AbstractNLPEvaluator} <: MPB.AbstractNLPEvaluator
    inner::T
    variable_map::Dict{MOI.VariableIndex, Int}
    num_inner_con::Int
    objective_expr::Union{Nothing, Expr}
    scalar_constraint_expr::Vector{Expr}
end

"""
MathProgBase expects expressions with variables denoted by `x[i]` for contiguous
`i`. However, JuMP 0.19 creates expressions with `x[MOI.VariableIndex(i)]`. So
we have to recursively walk the expression replacing instances of
MOI.VariableIndex by a corresponding integer.
"""
function replace_variableindex_by_int(variable_map, expr::Expr)
    for (i, arg) in enumerate(expr.args)
        expr.args[i] = replace_variableindex_by_int(variable_map, arg)
    end
    return expr
end
function replace_variableindex_by_int(variable_map, expr::MOI.VariableIndex)
    return variable_map[expr]
end
replace_variableindex_by_int(variable_map, expr) = expr

function MPB.initialize(d::NLPEvaluator, requested_features::Vector{Symbol})
    MOI.initialize(d.inner, requested_features)
    return
end

function MPB.features_available(d::NLPEvaluator)
    return MOI.features_available(d.inner)
end

function MPB.obj_expr(d::NLPEvaluator)
    if d.objective_expr !=== nothing
        return d.objective_expr
    else
        expr = MOI.objective_expr(d.inner)
        return replace_variableindex_by_int(d.variable_map, expr)
    end
end

function MPB.constr_expr(d::NLPEvaluator, i)
    if i <= d.num_inner_con
        expr = MOI.constraint_expr(d.inner, i)
        return replace_variableindex_by_int(d.variable_map, expr)
    else
        return d.scalar_constraint_expr[i - d.num_inner_con]
    end
end

function func_to_expr_graph(func::MOI.SingleVariable, variable_map)
    return Expr(:ref, :x, variable_map[func.variable])
end

function func_to_expr_graph(func::MOI.ScalarAffineFunction, variable_map)
    expr = Expr(:call, :+, func.constant)
    for term in func.terms
        coef = term.coefficient
        variable_int = variable_map[term.variable_index]
        push!(expr.args, Expr(:ref, :x, variable_int))
    end
    return expr
end

function func_to_expr_graph(func::MOI.ScalarQuadraticFunction, variable_map)
    expr = Expr(:call, :+, func.constant)
    for term in func.affine_terms
        coef = term.coefficient
        variable_int = variable_map[term.variable_index]
        push!(expr.args, Expr(:ref, :x, variable_int))
    end
    for term in func.quadratic_terms
        coef = term.coefficient
        variable_int_1 = variable_map[term.variable_index_1]
        variable_int_2 = variable_map[term.variable_index_2]
        push!(expr.args, Expr(
            :call,
            :*,
            Expr(:ref, :x, variable_int_1),
            Expr(:ref, :x, variable_int_2)
        ))
    end
    return expr
end

function funcset_to_expr_graph(func::Expr, set::MOI.LessThan)
    return Expr(:call, :<=, func, set.upper)
end

function funcset_to_expr_graph(func::Expr, set::MOI.GreaterThan)
    return Expr(:call, :>=, func, set.lower)
end

function funcset_to_expr_graph(func::Expr, set::MOI.EqualTo)
    return Expr(:call, :(==), func, set.value)
end

function funcset_to_expr_graph(func::Expr, set::MOI.Interval)
    return Expr(:comparison, set.lower, :<=, func, :<=, set.upper)
end

function moi_to_expr_graph(func::MOI.ScalarAffineFunction, set, variable_map)
    func_expr = func_to_expr_graph(func, variable_map)
    return funcset_to_expr_graph(func_expr, set)
end

function MOI.optimize!(model::Model)
    mpb_solver = MOI.get(model, MPBSolver())

    # Get the optimzation sense.
    opt_sense = MOI.get(model, MOI.ObjectiveSense())
    sense = opt_sense == MOI.MAX_SENSE ? :Max : :Min

    nlp_block = try
        MOI.get(model, MOI.NLPBlock())
    catch ex
        error("Expected a NLPBLock.")
    end

    # ==========================================================================
    # Extrac the constraint bounds.
    num_con = length(nlp_block.constraint_bounds)
    g_l = fill(-Inf, num_con)
    g_u = fill(Inf, num_con)
    for (i, bound) in enumerate(nlp_block.constraint_bounds)
        g_l[i] = bound.lower
        g_u[i] = bound.upper
    end

    # ==========================================================================
    # Intialize the variables. We need to form a mapping between the MOI
    # VariableIndex and an Int in order to replace instances of
    # `x[VariableIndex]` with `x[i]` in the expression graphs.
    variables = MOI.get(model, MOI.ListOfVariableIndices())
    num_var = length(variables)
    variable_map = Dict{MOI.VariableIndex, Int}()
    for (i, variable) in enumerate(variables)
        variable_map[variable] = i
    end

    # ==========================================================================
    # Extract variable bounds.
    x_l = fill(-Inf, num_var)
    x_u = fill(Inf, num_var)
    for set_type in MOI_SCALAR_SETS
        for c_ref in MOI.get(model,
            MOI.ListOfConstraintIndices{MOI.SingleVariable, set_type}())
            c_func = MOI.get(model, MOI.ConstraintFunction(), c_ref)
            c_set = MOI.get(model, MOI.ConstraintSet(), c_ref)
            v_index = variable_map[c_func.variable]
            lower, upper = set_to_bounds(c_set)
            x_l[v_index] = lower
            x_u[v_index] = upper
        end
    end

    # ==========================================================================
    # We have to convert all ScalarAffineFunction-in-Set constraints to an
    # expression graph.
    scalar_constraint_expr = Expr[]
    for set_type in MOI_SCALAR_SETS
        for c_ref in MOI.get(model, MOI.ListOfConstraintIndices{
                MOI.ScalarAffineFunction{Float64}, set_type}())
            c_func = MOI.get(model, MOI.ConstraintFunction(), c_ref)
            c_set = MOI.get(model, MOI.ConstraintSet(), c_ref)
            expr = moi_to_expr_graph(c_func, c_set, variable_map)
            push!(scalar_constraint_expr, expr)
            lower, upper = set_to_bounds(c_set)
            push!(g_l, lower)
            push!(g_u, upper)
        end
    end

    # ==========================================================================
    # MOI objective
    obj_type = MOI.get(model, MOI.ObjectiveFunctionType())
    obj_func = MOI.get(model, MOI.ObjeciveFunction{obj_type}())
    obj_func_expr = func_to_expr_graph(obj_func, variable_map)
    if obj_func_expr == :(+ 0.0)
        obj_func_expr = nothing
    end

    # ==========================================================================
    # Build the nlp_evaluator
    scalar_constraint_expr = Expr[]
    nlp_evaluator = NLPEvaluator(nlp_block.evaluator, variable_map, num_con,
        obj_func_expr, scalar_constraint_expr)

    # ==========================================================================
    # Create the MathProgBase model. Note that we pass `num_con` and the number
    # of linear constraints.
    mpb_model = MPB.NonlinearModel(mpb_solver)
    MPB.loadproblem!( mpb_model, num_var,
        num_con + length(scalar_constraint_expr), x_l, x_u, g_l, g_u, sense,
        nlp_evaluator)

    # ==========================================================================
    # Set any variables to :Bin if they are in ZeroOne and :Int if they are
    # Integer. The default is just :Cont.
    x_cat = fill(:Cont, num_var)
    for set_type in (MOI.ZeroOne, MOI.Integer)
        for c_ref in MOI.get(model,
            MOI.ListOfConstraintIndices{MOI.SingleVariable, set_type}())
            c_func = MOI.get(model, MOI.ConstraintFunction(), c_ref)
            c_set = MOI.get(model, MOI.ConstraintSet(), c_ref)
            v_index = variable_map[c_func.variable]
            x_cat[v_index] = set_to_cat(c_set)
        end
    end
    MPB.setvartype!(mpb_model, x_cat)

    # ==========================================================================
    # Set the VariablePrimalStart attributes for variables.
    variable_primal_start = fill(NaN, num_var)
    for (i, variable) in enumerate(variables)
        variable_primal_start[i] =
            MOI.get(model, MOI.VariablePrimalStart(), variable)
    end
    MPB.setwarmstart!(mpb_model, variable_primal_start)

    # ==========================================================================
    # Set the VariablePrimalStart attributes for variables.
    MPB.optimize!(mpb_model)

    # ==========================================================================
    # Extract and save the MathProgBase solution.
    primal_solution = Dict{MOI.VariableIndex, Float64}()
    for (variable, sol) in zip(variables, MPB.getsolution(mpb_model))
        primal_solution[variable] = sol
    end
    mpb_solution = MPBSolution(
        MPB.status(mpb_model),
        sense == :Min,
        MPB.getobjval(mpb_model),
        primal_solution
    )
    MOI.set(model, MPBSolutionAttribute(), mpb_solution)
    return
end

function MOI.get(model::Model, ::MOI.VariablePrimal, var::MOI.VariableIndex)
    mpb_solution = MOI.get(model, MPBSolutionAttribute())
    if mpb_solution === nothing
        return nothing
    end
    return mpb_solution.primal_solution[var]
end

function MOI.get(model::Model, ::MOI.ObjectiveValue)
    mpb_solution = MOI.get(model, MPBSolutionAttribute())
    if mpb_solution === nothing
        return nothing
    end
    return mpb_solution.objective_value
end

function MOI.get(model::Model, ::MOI.TerminationStatus)
    mpb_solution = MOI.get(model, MPBSolutionAttribute())
    if mpb_solution === nothing
        return MOI.OPTIMIZE_NOT_CALLED
    end
    status = mpb_solution.status
    if status == :Optimal
        return MOI.LOCALLY_SOLVED
    elseif status == :Infeasible
        return MOI.INFEASIBLE
    elseif status == :Unbounded
        return MOI.DUAL_INFEASIBLE
    elseif status == :UserLimit
        return MOI.OTHER_LIMIT
    elseif status == :Error
        return MOI.OTHER_ERROR
    end
    return MOI.OTHER_ERROR
end

function MOI.get(model::Model, ::MOI.PrimalStatus)
    mpb_solution = MOI.get(model, MPBSolutionAttribute())
    if mpb_solution === nothing
        return MOI.NO_SOLUTION
    end
    status = mpb_solution.status
    if status == :Optimal
        return MOI.FEASIBLE_POINT
    end
    return MOI.NO_SOLUTION
end

function MOI.get(model::Model, ::MOI.DualStatus)
    return MOI.NO_SOLUTION
end

function MOI.get(model::Model, ::MOI.ResultCount)
    if MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        return 1
    else
        return 0
    end
end
