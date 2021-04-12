module AmplNLWriter

import MathOptInterface
const MOI = MathOptInterface

include("NLExpr.jl")

### ============================================================================
### Nonlinear constraints
### ============================================================================

struct _NLConstraint
    lower::Float64
    upper::Float64
    opcode::Int
    expr::_NLExpr
end

"""
    _NLConstraint(expr::Expr, bound::MOI.NLPBoundsPair)

Convert a constraint in the form of a `expr` into a `_NLConstraint` object.

See `MOI.constraint_expr` for details on the format.

As a validation step, the right-hand side of each constraint must be a constant
term that is given by the `bound`. (If the constraint is an interval constraint,
both the left-hand and right-hand sides must be constants.)

The six NL constraint types are:

    l <= g(x) <= u : 0
         g(x) >= l : 1
         g(x) <= u : 2
         g(x)      : 3  # We don't support this
         g(x) == c : 4
     x ⟂ g(x)      : 5  # TODO(odow): Complementarity constraints
"""
function _NLConstraint(expr::Expr, bound::MOI.NLPBoundsPair)
    if expr.head == :comparison
        @assert length(expr.args) == 5
        if !(expr.args[1] ≈ bound.lower && bound.upper ≈ expr.args[5])
            _warn_invalid_bound(expr, bound)
        end
        return _NLConstraint(
            expr.args[1],
            expr.args[5],
            0,
            _NLExpr(expr.args[3]),
        )
    else
        @assert expr.head == :call
        @assert length(expr.args) == 3
        if expr.args[1] == :(<=)
            if !(-Inf ≈ bound.lower && bound.upper ≈ expr.args[3])
                _warn_invalid_bound(expr, bound)
            end
            return _NLConstraint(-Inf, expr.args[3], 1, _NLExpr(expr.args[2]))
        elseif expr.args[1] == :(>=)
            if !(expr.args[3] ≈ bound.lower && bound.upper ≈ Inf)
                _warn_invalid_bound(expr, bound)
            end
            return _NLConstraint(expr.args[3], Inf, 2, _NLExpr(expr.args[2]))
        else
            @assert expr.args[1] == :(==)
            if !(expr.args[3] ≈ bound.lower ≈ bound.upper)
                _warn_invalid_bound(expr, bound)
            end
            return _NLConstraint(
                expr.args[3],
                expr.args[3],
                4,
                _NLExpr(expr.args[2]),
            )
        end
    end
end

function _warn_invalid_bound(expr::Expr, bound::MOI.NLPBoundsPair)
    return @warn(
        "Invalid bounds detected in nonlinear constraint. Expected " *
        "`$(bound.lower) <= g(x) <= $(bound.upper)`, but got the constraint " *
        "$(expr)",
    )
end

### ============================================================================
### Nonlinear models
### ============================================================================

@enum(_VariableType, _BINARY, _INTEGER, _CONTINUOUS)

mutable struct _VariableInfo
    # Variable lower bound.
    lower::Float64
    # Variable upper bound.
    upper::Float64
    # Whether variable is binary or integer.
    type::_VariableType
    # Primal start of the variable.
    start::Union{Float64,Nothing}
    # Number of constraints that the variable appears in.
    jacobian_count::Int
    # If the variable appears in the objective.
    in_nonlinear_objective::Bool
    # If the objetive appears in a nonlinear constraint.
    in_nonlinear_constraint::Bool
    # The 0-indexed column of the variable. Computed right at the end.
    order::Int
    function _VariableInfo()
        return new(-Inf, Inf, _CONTINUOUS, nothing, 0, false, false, 0)
    end
end

struct _NLResults
    raw_status_string::String
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    objective_value::Float64
    primal_solution::Dict{MOI.VariableIndex,Float64}
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
_solver_command(x::String) = f -> f(x)
_solver_command(x::Function) = x

mutable struct Optimizer <: MOI.AbstractOptimizer
    optimizer::Function
    options::Dict{String,Any}
    stdin::IO
    stdout::IO
    results::_NLResults
    # Store MOI.Name().
    name::String
    # The objective expression.
    f::_NLExpr
    sense::MOI.OptimizationSense
    # A vector of nonlinear constraints
    g::Vector{_NLConstraint}
    # A vector of linear constraints
    h::Vector{_NLConstraint}
    # A dictionary of info for the variables.
    x::Dict{MOI.VariableIndex,_VariableInfo}
    # A struct to help sort the mess that is variable ordering in NL files.
    types::Vector{Vector{MOI.VariableIndex}}
    # A vector of the final ordering of the variables.
    order::Vector{MOI.VariableIndex}
end

"""
    Optimizer(
        solver_command::Union{String,Function},
        solver_args::Vector{String};
        stdin::IO = stdin,
        stdout::IO = stdout,
    )

Create a new Optimizer object.

`solver_command` should be one of two things:

* A `String` of the full path of an AMPL-compatible executable
* A function that takes takes a function as input, initializes any environment
  as needed, calls the input function with a path to the initialized executable,
  and then destructs the environment.

`solver_args` is a vector of `String` arguments passed solver executable.
However, prefer passing `key=value` options via `MOI.RawParameter`.

Redirect IO using `stdin` and `stdout`.

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
MOI.set(model, MOI.RawParameter("print_level"), 0
```
"""
function Optimizer(
    solver_command::Union{String,Function} = "",
    solver_args::Vector{String} = String[];
    stdin::IO = stdin,
    stdout::IO = stdout,
)
    return Optimizer(
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
        ),
        "",
        _NLExpr(false, _NLTerm[], Dict{MOI.VariableIndex,Float64}(), 0.0),
        MOI.FEASIBILITY_SENSE,
        _NLConstraint[],
        _NLConstraint[],
        Dict{MOI.VariableIndex,_VariableInfo}(),
        [MOI.VariableIndex[] for _ in 1:9],
        MOI.VariableIndex[],
    )
end

Base.show(io::IO, ::Optimizer) = print(io, "An AMPL (.nl) model")

MOI.get(model::Optimizer, ::MOI.SolverName) = "AmplNLWriter"

MOI.supports(::Optimizer, ::MOI.NLPBlock) = true

MOI.supports(::Optimizer, ::MOI.Name) = true
MOI.get(model::Optimizer, ::MOI.Name) = model.name
MOI.set(model::Optimizer, ::MOI.Name, name::String) = (model.name = name)

function MOI.empty!(model::Optimizer)
    model.results = _NLResults(
        "Optimize not called.",
        MOI.OPTIMIZE_NOT_CALLED,
        MOI.NO_SOLUTION,
        NaN,
        Dict{MOI.VariableIndex,Float64}(),
    )
    model.f = _NLExpr(false, _NLTerm[], Dict{MOI.VariableIndex,Float64}(), 0.0)
    empty!(model.g)
    empty!(model.h)
    empty!(model.x)
    for i in 1:9
        empty!(model.types[i])
    end
    empty!(model.order)
    return
end

function MOI.is_empty(model::Optimizer)
    return isempty(model.g) && isempty(model.h) && isempty(model.x)
end

const _SCALAR_FUNCTIONS = Union{
    MOI.SingleVariable,
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
    ::Type{MOI.SingleVariable},
    ::Type{<:Union{MOI.ZeroOne,MOI.Integer}},
)
    return true
end

MOI.supports(::Optimizer, ::MOI.ObjectiveSense) = true
MOI.supports(::Optimizer, ::MOI.ObjectiveFunction{<:_SCALAR_FUNCTIONS}) = true

MOI.supports(::Optimizer, ::MOI.RawParameter) = true
function MOI.get(model::Optimizer, attr::MOI.RawParameter)
    return get(model.options, attr.name, nothing)
end
function MOI.set(model::Optimizer, attr::MOI.RawParameter, value)
    model.options[attr.name] = value
    return
end

# ==============================================================================

function MOI.supports(
    ::Optimizer,
    ::MOI.VariablePrimalStart,
    ::Type{MOI.VariableIndex},
)
    return true
end

function MOI.set(model::Optimizer, ::MOI.VariablePrimalStart, x, v::Real)
    model.x[x].start = Float64(v)
    return
end

function MOI.set(model::Optimizer, ::MOI.VariablePrimalStart, x, ::Nothing)
    model.x[x].start = nothing
    return
end

function MOI.get(
    model::Optimizer,
    ::MOI.VariablePrimalStart,
    x::MOI.VariableIndex,
)
    return model.x[x].start
end

# ==============================================================================

struct _LinearNLPEvaluator <: MOI.AbstractNLPEvaluator end
MOI.features_available(::_LinearNLPEvaluator) = [:ExprGraph]
MOI.initialize(::_LinearNLPEvaluator, ::Vector{Symbol}) = nothing

MOI.Utilities.supports_default_copy_to(::Optimizer, ::Bool) = false

function MOI.copy_to(
    dest::Optimizer,
    model::MOI.ModelLike;
    copy_names::Bool = false,
)
    mapping = MOI.Utilities.IndexMap()
    # Initialize the NLP block.
    nlp_block = try
        MOI.get(model, MOI.NLPBlock())
    catch
        MOI.NLPBlockData(MOI.NLPBoundsPair[], _LinearNLPEvaluator(), false)
    end
    if !(:ExprGraph in MOI.features_available(nlp_block.evaluator))
        error(
            "Unable to use AmplNLWriter because the nonlinear evaluator " *
            "does not supply expression graphs.",
        )
    end
    MOI.initialize(nlp_block.evaluator, [:ExprGraph])
    # Objective function.
    if nlp_block.has_objective
        dest.f = _NLExpr(MOI.objective_expr(nlp_block.evaluator))
    else
        F = MOI.get(model, MOI.ObjectiveFunctionType())
        obj = MOI.get(model, MOI.ObjectiveFunction{F}())
        dest.f = _NLExpr(obj)
    end
    # Nonlinear constraints
    for (i, bound) in enumerate(nlp_block.constraint_bounds)
        push!(
            dest.g,
            _NLConstraint(MOI.constraint_expr(nlp_block.evaluator, i), bound),
        )
    end
    for x in MOI.get(model, MOI.ListOfVariableIndices())
        dest.x[x] = _VariableInfo()
        start = MOI.get(model, MOI.VariablePrimalStart(), x)
        MOI.set(dest, MOI.VariablePrimalStart(), x, start)
        mapping[x] = x
    end
    dest.sense = MOI.get(model, MOI.ObjectiveSense())
    resize!(dest.order, length(dest.x))
    # Now deal with the normal MOI constraints.
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        _process_constraint(dest, model, F, S, mapping)
    end
    # Correct bounds of binary variables. Mainly because AMPL doesn't have the
    # concept of binary nonlinear variables, but it does have binary linear
    # variables! How annoying.
    for (x, v) in dest.x
        if v.type == _BINARY
            v.lower = max(0.0, v.lower)
            v.upper = min(1.0, v.upper)
        end
    end
    # Jacobian counts. The zero terms for nonlinear constraints should have
    # been added when the expression was constructed.
    for g in dest.g, v in keys(g.expr.linear_terms)
        dest.x[v].jacobian_count += 1
    end
    for h in dest.h, v in keys(h.expr.linear_terms)
        dest.x[v].jacobian_count += 1
    end
    # Now comes the confusing part.
    #
    # AMPL, in all its wisdom, orders variables in a _very_ specific way.
    # The only hint in "Writing NL files" is the line "Variables are ordered as
    # described in Tables 3 and 4 of [5]".
    #
    # Reading these
    #
    # https://cfwebprod.sandia.gov/cfdocs/CompResearch/docs/nlwrite20051130.pdf
    # https://ampl.com/REFS/hooking2.pdf
    #
    # leads us to the following order
    #
    # 1) Continuous variables that appear in a
    #       nonlinear objective AND a nonlinear constraint
    # 2) Discrete variables that appear in a
    #       nonlinear objective AND a nonlinear constraint
    # 3) Continuous variables that appear in a
    #       nonlinear constraint, but NOT a nonlinear objective
    # 4) Discrete variables that appear in a
    #       nonlinear constraint, but NOT a nonlinear objective
    # 5) Continuous variables that appear in a
    #       nonlinear objective, but NOT a nonlinear constraint
    # 6) Discrete variables that appear in a
    #       nonlinear objective, but NOT a nonlinear constraint
    # 7) Continuous variables that DO NOT appear in a
    #       nonlinear objective or a nonlinear constraint
    # 8) Binary variables that DO NOT appear in a
    #       nonlinear objective or a nonlinear constraint
    # 9) Integer variables that DO NOT appear in a
    #       nonlinear objective or a nonlinear constraint
    #
    # Yes, nonlinear variables are broken into continuous/discrete, but linear
    # variables are partitioned into continuous, binary, and integer. (See also,
    # the need to modify bounds for binary variables.)
    if !dest.f.is_linear
        for x in keys(dest.f.linear_terms)
            dest.x[x].in_nonlinear_objective = true
        end
        for x in dest.f.nonlinear_terms
            if x isa MOI.VariableIndex
                dest.x[x].in_nonlinear_objective = true
            end
        end
    end
    for con in dest.g
        for x in keys(con.expr.linear_terms)
            dest.x[x].in_nonlinear_constraint = true
        end
        for x in con.expr.nonlinear_terms
            if x isa MOI.VariableIndex
                dest.x[x].in_nonlinear_constraint = true
            end
        end
    end
    types = dest.types
    for (x, v) in dest.x
        if v.in_nonlinear_constraint && v.in_nonlinear_objective
            push!(v.type == _CONTINUOUS ? types[1] : types[2], x)
        elseif v.in_nonlinear_constraint
            push!(v.type == _CONTINUOUS ? types[3] : types[4], x)
        elseif v.in_nonlinear_objective
            push!(v.type == _CONTINUOUS ? types[5] : types[6], x)
        elseif v.type == _CONTINUOUS
            push!(types[7], x)
        elseif v.type == _BINARY
            push!(types[8], x)
        else
            @assert v.type == _INTEGER
            push!(types[9], x)
        end
    end
    # However! Don't let Tables 3 and 4 fool you, because the ordering actually
    # depends on whether the number of nonlinear variables in the objective only
    # is _strictly_ greater than the number of nonlinear variables in the
    # constraints only. Quoting:
    #
    #   For all versions, the first nlvc variables appear nonlinearly in at
    #   least one constraint. If nlvo > nlvc, the first nlvc variables may or
    #   may not appear nonlinearly in an objective, but the next nlvo – nlvc
    #   variables do appear nonlinearly in at least one objective. Otherwise
    #   all of the first nlvo variables appear nonlinearly in an objective.
    #
    # However, even this is slightly incorrect, because I think it should read
    # "For all versions, the first nlvb variables appear nonlinearly." The "nlvo
    # - nlvc" part is also clearly incorrect, and should probably read "nlvo -
    # nlvb."
    #
    # It's a bit confusing, so here is the relevant code from Couenne:
    # https://github.com/coin-or/Couenne/blob/683c5b305d78a009d59268a4bca01e0ad75ebf02/src/readnl/readnl.cpp#L76-L87
    #
    # They interpret this paragraph to mean the switch on nlvo > nlvc determines
    # whether the next block of variables are the ones that appear in the
    # objective only, or the constraints only.
    #
    # That makes sense as a design choice, because you can read them in two
    # contiguous blocks.
    #
    # Essentially, what all this means is if !(nlvo > nlvc), then swap 3-4 for
    # 5-6 in the variable order.
    nlvc = length(types[3]) + length(types[4])
    nlvo = length(types[5]) + length(types[6])
    order_i = if nlvo > nlvc
        [1, 2, 3, 4, 5, 6, 7, 8, 9]
    else
        [1, 2, 5, 6, 3, 4, 7, 8, 9]
    end
    # Now we can order the variables.
    n = 0
    for i in order_i
        # Since variables come from a dictionary, there may be differences in
        # the order depending on platform and Julia version. Sort by creation
        # time for consistency.
        for x in sort!(types[i]; by = y -> y.value)
            dest.x[x].order = n
            dest.order[n+1] = x
            n += 1
        end
    end
    return mapping
end

_set_to_bounds(set::MOI.Interval) = (0, set.lower, set.upper)
_set_to_bounds(set::MOI.LessThan) = (1, -Inf, set.upper)
_set_to_bounds(set::MOI.GreaterThan) = (2, set.lower, Inf)
_set_to_bounds(set::MOI.EqualTo) = (4, set.value, set.value)

function _process_constraint(dest::Optimizer, model, F, S, mapping)
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(model, MOI.ConstraintFunction(), ci)
        s = MOI.get(model, MOI.ConstraintSet(), ci)
        op, l, u = _set_to_bounds(s)
        con = _NLConstraint(l, u, op, _NLExpr(f))
        if isempty(con.expr.linear_terms) && isempty(con.expr.nonlinear_terms)
            if l <= con.expr.constant <= u
                continue
            else
                error(
                    "Malformed constraint. There are no variables and the " *
                    "bounds don't make sense.",
                )
            end
        elseif con.expr.is_linear
            push!(dest.h, con)
            mapping[ci] = MOI.ConstraintIndex{F,S}(length(dest.h))
        else
            push!(dest.g, con)
            mapping[ci] = MOI.ConstraintIndex{F,S}(length(dest.g))
        end
    end
    return
end

function _process_constraint(
    dest::Optimizer,
    model,
    F::Type{MOI.SingleVariable},
    S,
    mapping,
)
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        mapping[ci] = ci
        f = MOI.get(model, MOI.ConstraintFunction(), ci)
        s = MOI.get(model, MOI.ConstraintSet(), ci)
        _, l, u = _set_to_bounds(s)
        if l > -Inf
            dest.x[f.variable].lower = l
        end
        if u < Inf
            dest.x[f.variable].upper = u
        end
    end
    return
end

function _process_constraint(
    dest::Optimizer,
    model,
    F::Type{MOI.SingleVariable},
    S::Union{Type{MOI.ZeroOne},Type{MOI.Integer}},
    mapping,
)
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        mapping[ci] = ci
        f = MOI.get(model, MOI.ConstraintFunction(), ci)
        dest.x[f.variable].type = S == MOI.ZeroOne ? _BINARY : _INTEGER
    end
    return
end

_str(x::Float64) = isinteger(x) ? string(round(Int, x)) : string(x)

_write_term(io, x::Float64, ::Any) = println(io, "n", _str(x))
_write_term(io, x::Int, ::Any) = println(io, "o", x)
function _write_term(io, x::MOI.VariableIndex, nlmodel)
    return println(io, "v", nlmodel.x[x].order)
end

_is_nary(x::Int) = x in _NARY_OPCODES
_is_nary(x) = false

function _write_nlexpr(io::IO, expr::_NLExpr, nlmodel::Optimizer)
    if expr.is_linear || length(expr.nonlinear_terms) == 0
        # If the expression is linear, just write out the constant term.
        _write_term(io, expr.constant, nlmodel)
        return
    end
    # If the constant term is non-zero, we need to write it out.
    skip_terms = 0
    if !iszero(expr.constant)
        if expr.nonlinear_terms[1] == OPSUMLIST
            # The nonlinear expression is a summation. We can write our constant
            # first, but we also need to increment the number of arguments by
            # one. In addition, since we're writing out the first two terms now,
            # we must skip them below.
            _write_term(io, OPSUMLIST, nlmodel)
            println(io, expr.nonlinear_terms[2] + 1)
            _write_term(io, expr.constant, nlmodel)
            skip_terms = 2
        else
            # The nonlinear expression is something other than a summation, so
            # add a new + node to the expression.
            _write_term(io, OPPLUS, nlmodel)
            _write_term(io, expr.constant, nlmodel)
        end
    end
    last_nary = false
    for term in expr.nonlinear_terms
        if skip_terms > 0
            skip_terms -= 1
            continue
        end
        if last_nary
            println(io, term::Int)
            last_nary = false
        else
            _write_term(io, term, nlmodel)
            last_nary = _is_nary(term)
        end
    end
    return
end

function _write_linear_block(io::IO, expr::_NLExpr, nlmodel::Optimizer)
    elements = [(c, nlmodel.x[v].order) for (v, c) in expr.linear_terms]
    for (c, x) in sort!(elements; by = i -> i[2])
        println(io, x, " ", _str(c))
    end
    return
end

function Base.write(io::IO, nlmodel::Optimizer)
    # ==========================================================================
    # Header
    # Line 1: Always the same
    # Notes:
    #  * I think these are magic bytes used by AMPL internally for stuff.
    println(io, "g3 1 1 0")

    # Line 2: vars, constraints, objectives, ranges, eqns, logical constraints
    # Notes:
    #  * We assume there is always one objective, even if it is just `min 0`.
    n_con, n_ranges, n_eqns = 0, 0, 0
    for cons in (nlmodel.g, nlmodel.h), c in cons
        n_con += 1
        if c.opcode == 0
            n_ranges += 1
        elseif c.opcode == 4
            n_eqns += 1
        end
    end
    println(io, " $(length(nlmodel.x)) $(n_con) 1 $(n_ranges) $(n_eqns) 0")

    # Line 3: nonlinear constraints, objectives
    # Notes:
    #  * We assume there is always one objective, even if it is just `min 0`.
    n_nlcon = length(nlmodel.g)
    println(io, " ", n_nlcon, " ", 1)

    # Line 4: network constraints: nonlinear, linear
    # Notes:
    #  * We don't support network constraints. I don't know how they are
    #    represented.
    println(io, " 0 0")

    # Line 5: nonlinear vars in constraints, objectives, both
    # Notes:
    #  * This order is confusingly different to the standard "b, c, o" order.
    nlvb = length(nlmodel.types[1]) + length(nlmodel.types[2])
    nlvc = nlvb + length(nlmodel.types[3]) + length(nlmodel.types[4])
    nlvo = nlvb + length(nlmodel.types[5]) + length(nlmodel.types[6])
    println(io, " ", nlvc, " ", nlvo, " ", nlvb)

    # Line 6: linear network variables; functions; arith, flags
    # Notes:
    #  * I don't know what this line means. It is what it is. Apparently `flags`
    #    is set to 1 to get suffixes in .sol file.
    println(io, " 0 0 0 1")

    # Line 7: discrete variables: binary, integer, nonlinear (b,c,o)
    # Notes:
    #  * The order is
    #    - binary variables in linear only
    #    - integer variables in linear only
    #    - binary or integer variables in nonlinear objective and constraint
    #    - binary or integer variables in nonlinear constraint
    #    - binary or integer variables in nonlinear objective
    nbv = length(nlmodel.types[8])
    niv = length(nlmodel.types[9])
    nl_both = length(nlmodel.types[2])
    nl_cons = length(nlmodel.types[4])
    nl_obj = length(nlmodel.types[6])
    println(io, " ", nbv, " ", niv, " ", nl_both, " ", nl_cons, " ", nl_obj)

    # Line 8: nonzeros in Jacobian, gradients
    # Notes:
    #  * Make sure to include a 0 element for every variable that appears in an
    #    objective or constraint, even if the linear coefficient is 0.
    nnz_jacobian = 0
    for g in nlmodel.g
        nnz_jacobian += length(g.expr.linear_terms)
    end
    for h in nlmodel.h
        nnz_jacobian += length(h.expr.linear_terms)
    end
    nnz_gradient = length(nlmodel.f.linear_terms)
    println(io, " ", nnz_jacobian, " ", nnz_gradient)

    # Line 9: max name lengths: constraints, variables
    # Notes:
    #  * We don't add names, so this is just 0, 0.
    println(io, " 0 0")

    # Line 10: common exprs: b,c,o,c1,o1
    # Notes:
    #  * We don't add common subexpressions (i.e., V blocks).
    #  * I assume the notation means
    #     - b = in nonlinear objective and constraint
    #     - c = in nonlinear constraint
    #     - o = in nonlinear objective
    #     - c1 = in linear constraint
    #     - o1 = in linear objective
    println(io, " 0 0 0 0 0")
    # ==========================================================================
    # Constraints
    # Notes:
    #  * Nonlinear constraints first, then linear.
    #  * For linear constraints, write out the constant term here.
    for (i, g) in enumerate(nlmodel.g)
        println(io, "C", i - 1)
        _write_nlexpr(io, g.expr, nlmodel)
    end
    for (i, h) in enumerate(nlmodel.h)
        println(io, "C", i - 1 + n_nlcon)
        _write_nlexpr(io, h.expr, nlmodel)
    end
    # ==========================================================================
    # Objective
    # Notes:
    #  * NL files support multiple objectives, but we're just going to write 1,
    #    so it's always `O0`.
    #  * For linear objectives, write out the constant term here.
    println(io, "O0 ", nlmodel.sense == MOI.MAX_SENSE ? "1" : "0")
    _write_nlexpr(io, nlmodel.f, nlmodel)
    # ==========================================================================
    # VariablePrimalStart
    # Notes:
    #  * Make sure to write out the variables in order.
    println(io, "x", length(nlmodel.x))
    for (i, x) in enumerate(nlmodel.order)
        start = MOI.get(nlmodel, MOI.VariablePrimalStart(), x)
        println(io, i - 1, " ", start === nothing ? 0 : _str(start))
    end
    # ==========================================================================
    # Constraint bounds
    # Notes:
    #  * Nonlinear constraints go first, then linear.
    #  * The constant term for linear constraints gets written out in the
    #    "C" block.
    if n_con > 0
        println(io, "r")
        # Nonlinear constraints
        for g in nlmodel.g
            print(io, g.opcode)
            if g.opcode == 0
                println(io, " ", _str(g.lower), " ", _str(g.upper))
            elseif g.opcode == 1
                println(io, " ", _str(g.upper))
            elseif g.opcode == 2
                println(io, " ", _str(g.lower))
            else
                @assert g.opcode == 4
                println(io, " ", _str(g.lower))
            end
        end
        # Linear constraints
        for h in nlmodel.h
            print(io, h.opcode)
            if h.opcode == 0
                println(io, " ", _str(h.lower), " ", _str(h.upper))
            elseif h.opcode == 1
                println(io, " ", _str(h.upper))
            elseif h.opcode == 2
                println(io, " ", _str(h.lower))
            else
                @assert h.opcode == 4
                println(io, " ", _str(h.lower))
            end
        end
    end
    # ==========================================================================
    # Variable bounds
    # Notes:
    #  * Not much to note, other than to make sure you iterate the variables in
    #    the correct order.
    println(io, "b")
    for x in nlmodel.order
        v = nlmodel.x[x]
        if v.lower == v.upper
            println(io, "4 ", _str(v.lower))
        elseif -Inf < v.lower && v.upper < Inf
            println(io, "0 ", _str(v.lower), " ", _str(v.upper))
        elseif -Inf == v.lower && v.upper < Inf
            println(io, "1 ", _str(v.upper))
        elseif -Inf < v.lower && v.upper == Inf
            println(io, "2 ", _str(v.lower))
        else
            println(io, "3")
        end
    end
    # ==========================================================================
    # Jacobian block
    # Notes:
    #  * If a variable appears in a constraint, it needs to have a corresponding
    #    entry in the Jacobian block, even if the linear coefficient is zero.
    #    AMPL uses this to determine the Jacobian sparsity.
    #  * As before, nonlinear constraints go first, then linear.
    #  * Don't write out the `k` entry for the last variable, because it can be
    #    inferred from the total number of elements in the Jacobian as given in
    #    the header.
    if n_con > 0
        println(io, "k", length(nlmodel.x) - 1)
        total = 0
        for i in 1:length(nlmodel.order)-1
            total += nlmodel.x[nlmodel.order[i]].jacobian_count
            println(io, total)
        end
        for (i, g) in enumerate(nlmodel.g)
            println(io, "J", i - 1, " ", length(g.expr.linear_terms))
            _write_linear_block(io, g.expr, nlmodel)
        end
        for (i, h) in enumerate(nlmodel.h)
            println(io, "J", i - 1 + n_nlcon, " ", length(h.expr.linear_terms))
            _write_linear_block(io, h.expr, nlmodel)
        end
    end
    # ==========================================================================
    # Gradient block
    # Notes:
    #  * You only need to write this out if there are linear terms in the
    #    objective.
    if nnz_gradient > 0
        println(io, "G0 ", nnz_gradient)
        _write_linear_block(io, nlmodel.f, nlmodel)
    end
    return nlmodel
end

"""
    _interpret_status(solve_result_num::Int, raw_status_string::String)

Convert the `solve_result_num` and `raw_status_string` into MOI-type statuses.

For the primal status, assume a solution is present. Other code is responsible
for returning `MOI.NO_SOLUTION` if no primal solution is present.
"""
function _interpret_status(solve_result_num::Int, raw_status_string::String)
    if 0 <= solve_result_num < 100
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT
    elseif 100 <= solve_result_num < 200
        return MOI.LOCALLY_SOLVED, MOI.UNKNOWN_RESULT_STATUS
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

function _read_sol(filename::String, model::Optimizer)
    return open(io -> _read_sol(io, model), filename, "r")
end

"""
    _read_sol(io::IO, model::Optimizer)

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
function _read_sol(io::IO, model::Optimizer)
    raw_status_string = ""
    line = ""
    while !startswith(line, "Options")
        line = _readline(io)
        raw_status_string *= line
    end
    # Read through all the options. Direct copy of reference implementation.
    @assert startswith(line, "Options")
    options = [_readline(io, Int), _readline(io, Int), _readline(io, Int)]
    num_options = options[1]
    if !(3 <= num_options <= 9)
        error("expected num_options between 3 and 9; " * "got $num_options")
    end
    need_vbtol = false
    if options[3] == 3
        num_options -= 2
        need_vbtol = true
    end
    for j in 3:num_options
        push!(options, _readline(io, Int))
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
    # TODO(odow): read in the dual solutions!
    for _ in 1:num_duals_to_read
        _readline(io)
    end
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
    termination_status, primal_status =
        _interpret_status(solve_result_num, raw_status_string)
    objective_value = NaN
    if length(primal_solution) > 0
        # .sol files don't seem to be able to return the objective
        # value. Evaluate it here instead.
        objective_value = _evaluate(model.f, primal_solution)
    end
    return _NLResults(
        raw_status_string,
        termination_status,
        length(primal_solution) > 0 ? primal_status : MOI.NO_SOLUTION,
        objective_value,
        primal_solution,
    )
end

function MOI.optimize!(model::Optimizer)
    temp_dir = mktempdir()
    nl_file = joinpath(temp_dir, "model.nl")
    open(io -> write(io, model), nl_file, "w")
    options = [isempty(v) ? k : "$(k)=$(v)" for (k, v) in model.options]
    try
        model.optimizer() do solver_path
            ret = run(
                pipeline(
                    `$(solver_path) $(nl_file) -AMPL $(options)`,
                    stdin = model.stdin,
                    stdout = model.stdout,
                ),
            )
            if ret.exitcode != 0
                error("Nonzero exit code: $(ret.exitcode)")
            end
        end
        model.results = _read_sol(joinpath(temp_dir, "model.sol"), model)
    catch err
        model.results = _NLResults(
            "Error calling the solver. Failed with: $(err)",
            MOI.OTHER_ERROR,
            MOI.NO_SOLUTION,
            NaN,
            Dict{MOI.VariableIndex,Float64}(),
        )
    end
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

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    return model.results.termination_status
end

function MOI.get(model::Optimizer, attr::MOI.PrimalStatus)
    return attr.N == 1 ? model.results.primal_status : MOI.NO_SOLUTION
end

MOI.get(::Optimizer, ::MOI.DualStatus) = MOI.NO_SOLUTION

function MOI.get(model::Optimizer, ::MOI.RawStatusString)
    return model.results.raw_status_string
end

function MOI.get(model::Optimizer, ::MOI.ResultCount)
    return MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT ? 1 : 0
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{<:MOI.SingleVariable},
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
    return _evaluate(model.h[ci.value].expr, model.results.primal_solution)
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{<:MOI.ScalarQuadraticFunction},
)
    MOI.check_result_index_bounds(model, attr)
    return _evaluate(model.g[ci.value].expr, model.results.primal_solution)
end

function MOI.write_to_file(model::Optimizer, filename::String)
    open(io -> write(io, model), filename, "w")
    return
end

end
