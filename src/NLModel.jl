include("opcode.jl")
include("rev_opcode.jl")

const _NLTerm = Union{Int,Float64,MOI.VariableIndex}

struct _NLExpr
    is_linear::Bool
    nonlinear_terms::Vector{_NLTerm}
    variables::Vector{MOI.VariableIndex}
    coefficients::Vector{Float64}
    constant::Float64
end

function _evaluate(expr::_NLExpr, x::Dict{MOI.VariableIndex,Float64})
    y = expr.constant
    for (c, v) in zip(expr.coefficients, expr.variables)
        y += c * x[v]
    end
    # TODO(odow): evaluate nonlinear terms
    return y
end

function Base.:(==)(x::_NLExpr, y::_NLExpr)
    return x.is_linear == y.is_linear &&
           x.nonlinear_terms == y.nonlinear_terms &&
           x.variables == y.variables &&
           x.coefficients == y.coefficients &&
           x.constant == y.constant
end

function _NLExpr(
    variables::Vector{MOI.VariableIndex},
    coefficients::Vector{Float64},
    constant::Float64,
)
    return _NLExpr(true, _NLTerm[], variables, coefficients, constant)
end

function _NLExpr(terms::Vector{_NLTerm})
    return _NLExpr(false, terms, MOI.VariableIndex[], Float64[], 0.0)
end

_NLExpr(x::MOI.VariableIndex) = _NLExpr(true, _NLTerm[], [x], [1.0], 0.0)

_NLExpr(x::MOI.SingleVariable) = _NLExpr(x.variable)

function _NLExpr(x::MOI.ScalarAffineFunction)
    N = length(x.terms)
    coefficients = Vector{Float64}(undef, N)
    variables = Vector{MOI.VariableIndex}(undef, N)
    for (i, term) in enumerate(x.terms)
        coefficients[i] = term.coefficient
        variables[i] = term.variable_index
    end
    return _NLExpr(variables, coefficients, x.constant)
end

function _NLExpr(x::MOI.ScalarQuadraticFunction)
    N = length(x.affine_terms)
    variables = Vector{MOI.VariableIndex}(undef, N)
    coefficients = Vector{Float64}(undef, N)
    for (i, term) in enumerate(x.affine_terms)
        variables[i] = term.variable_index
        coefficients[i] = term.coefficient
    end
    terms = _NLTerm[]
    if length(x.quadratic_terms) == 2
        push!(terms, OPPLUS)
    elseif length(x.quadratic_terms) > 2
        push!(terms, OPSUMLIST)
        push!(terms, length(x.quadratic_terms))
    end
    for term in x.quadratic_terms
        coefficient = term.coefficient
        if term.variable_index_1 == term.variable_index_2
            coefficient *= 0.5  # MOI defines quadratic as 1/2 x' Q x :(
        end
        if !isone(coefficient)
            push!(terms, OPMULT)
            push!(terms, coefficient)
        end
        push!(terms, OPMULT)
        push!(terms, term.variable_index_1)
        push!(terms, term.variable_index_2)
    end
    return _NLExpr(false, terms, variables, coefficients, x.constant)
end

function _NLExpr(expr::Expr)
    terms = _NLTerm[]
    _process_expr(terms, expr)
    # TODO(odow): detect linear expressions.
    return _NLExpr(terms)
end

function _process_expr(
    terms::Vector{_NLTerm},
    expr::Union{Real,MOI.VariableIndex},
)
    return push!(terms, expr)
end

function _process_expr(terms::Vector{_NLTerm}, expr::Expr)
    if expr.head == :call
        f = get(_UNARY_SPECIAL_CASES, expr.args[1], nothing)
        if f !== nothing && length(expr.args) == 2
            # Some unary-functions are special cased. See the associated comment
            # next to the definition of _UNARY_SPECIAL_CASES.
            _process_expr(terms, f(expr.args[2]))
        else
            _process_call(terms, expr.args)
        end
    elseif expr.head == :ref
        _process_expr(terms, expr.args[2])
    else
        error("Unsupported expression: $(expr)")
    end
    return
end

function _process_call(terms::Vector{_NLTerm}, args::Vector{Any})
    op = first(args)
    N = length(args) - 1
    # ==========================================================================
    # Before processing the arguments, do some re-writing.
    if op == :+
        if N == 1  # +x, so we can just drop the op and process the args.
            return _process_expr(terms, args[2])
        elseif N > 2  # nary-addition!
            op = :sum
        end
    elseif op == :- && N == 1
        op = :neg
    elseif op == :* && N > 2  # nary-multiplication.
        # NL doesn't define an nary multiplication operator, so we need to
        # rewrite our expression as a sequence of chained binary operators.
        while N > 2
            # Combine last term with previous to form a binary * expression
            arg = pop!(args)
            args[end] = Expr(:call, :*, args[end], arg)
            N = length(args) - 1
        end
    end
    # ==========================================================================
    opcode = get(_REV_OPCODES, op, nothing)
    if opcode === nothing
        error("Unsupported operation $(op)")
    end
    push!(terms, opcode)
    if opcode in _NARY_OPCODES
        push!(terms, N)
    end
    for i in 1:N
        _process_expr(terms, args[i+1])
    end
    return
end

struct _NLConstraint
    lower::Float64
    upper::Float64
    opcode::Int
    expr::_NLExpr
end

"""
    _NLConstraint(expr::Expr)

Convert a constraint in the form of an expression into a `_NLConstraint`
object. We have to make sure to move all constant terms into the bounds!

The six NL constraint types are:

    l <= g(x) <= u : 0
         g(x) >= l : 1
         g(x) <= u : 2
         g(x)      : 3  # We don't support this
         g(x) == c : 4
     x ⟂ g(x)      : 5  # TODO(odow): Complementarity constraints
"""
function _NLConstraint(expr::Expr)
    if expr.head == :comparison
        @assert length(expr.args) == 5
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
            return _NLConstraint(-Inf, expr.args[3], 1, _NLExpr(expr.args[2]))
        elseif expr.args[1] == :(>=)
            return _NLConstraint(expr.args[3], Inf, 2, _NLExpr(expr.args[2]))
        else
            @assert expr.args[1] == :(==)
            return _NLConstraint(
                expr.args[3],
                expr.args[3],
                4,
                _NLExpr(expr.args[2]),
            )
        end
    end
end

@enum(_VariableType, _BINARY, _INTEGER, _CONTINUOUS)
@enum(_LinearityType, _LINEAR, _NONLINEAR, _BOTH)

mutable struct _VariableInfo
    lower::Float64
    upper::Float64
    type::_VariableType
    start::Union{Float64,Nothing}
    jacobian_count::Int
    in_nonlinear_objective::Bool
    in_nonlinear_constraint::Bool
    order::Int
    function _VariableInfo(model::Optimizer, x::MOI.VariableIndex)
        start = MOI.get(model, MOI.VariablePrimalStart(), x)
        return new(-Inf, Inf, _CONTINUOUS, start, 0, false, false, 0)
    end
end

struct _NLModel
    f::_NLExpr
    sense::MOI.OptimizationSense
    g::Vector{_NLConstraint}
    h::Vector{_NLConstraint}
    x::Dict{MOI.VariableIndex,_VariableInfo}
    types::Vector{Vector{MOI.VariableIndex}}
    order::Vector{MOI.VariableIndex}
end

"""
    _NLModel(model::Optimizer)

Given a `MOI.FileFormats.NL.Model` object, return an `_NLModel` describing:

    sense f(x)
    s.t.  l_g <= g(x) <= u_g
          l_x <=   x  <= u_x
          x_cat_i ∈ {:Bin, :Int}
"""
function _NLModel(model::Optimizer)
    # ==========================================================================
    # Initialize the NLP block.
    nlp_block = MOI.get(model, MOI.NLPBlock())
    MOI.initialize(nlp_block.evaluator, [:ExprGraph])
    # ==========================================================================
    # Objective function.
    objective = if nlp_block.has_objective
        _NLExpr(MOI.objective_expr(nlp_block.evaluator))
    else
        F = MOI.get(model, MOI.ObjectiveFunctionType())
        obj = MOI.get(model, MOI.ObjectiveFunction{F}())
        _NLExpr(obj)
    end
    # ==========================================================================
    # Constraints
    N = length(nlp_block.constraint_bounds)
    g = [
        _NLConstraint(MOI.constraint_expr(nlp_block.evaluator, i)) for i in 1:N
    ]
    # ==========================================================================
    # _NLModel
    x = Dict{MOI.VariableIndex,_VariableInfo}(
        x => _VariableInfo(model, x) for
        x in MOI.get(model, MOI.ListOfVariableIndices())
    )
    nlmodel = _NLModel(
        objective,
        MOI.get(model, MOI.ObjectiveSense()),
        g,
        _NLConstraint[],
        x,
        [MOI.VariableIndex[] for _ in 1:9],
        Vector{MOI.VariableIndex}(undef, length(x)),
    )
    # ==========================================================================
    # Affine, Quadratic, and SingleVariable constraints
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        _process_constraint(nlmodel, model, F, S)
    end
    # ==========================================================================
    # Correct bounds of binary variables
    for (x, v) in nlmodel.x
        if v.type == _BINARY
            v.lower = max(0.0, v.lower)
            v.upper = min(1.0, v.upper)
        end
    end
    # ==========================================================================
    # Jacobian counts
    for g in nlmodel.g, v in g.expr.variables
        nlmodel.x[v].jacobian_count += 1
    end
    for h in nlmodel.h, v in h.expr.variables
        nlmodel.x[v].jacobian_count += 1
    end
    # ==========================================================================
    # AMPL, in all its wisdom, orders variables in a _very_ specific way.
    # The only hint in "Writing NL files" is the line "Variables are ordered as
    # described in Tables 3 and 4 of [5]," which leads us to the following order
    #
    # 1) Continuous variables that appear in a nonlinear objective AND a nonlinear constraint
    # 2) Discrete variables that appear in a nonlinear objective AND a nonlinear constraint
    # 3) Continuous variables that appear in a nonlinear constraint, but NOT a nonlinear objective
    # 4) Discrete variables that appear in a nonlinear constraint, but NOT a nonlinear objective
    # 5) Continuous variables that appear in a nonlinear objective, but NOT a nonlinear constraint
    # 6) Discrete variables that appear in a nonlinear objective, but NOT a nonlinear constraint
    # 7) Continuous variables that DO NOT appear in a nonlinear objective or a nonlinear constraint
    # 8) Binary variables that DO NOT appear in a nonlinear objective or a nonlinear constraint
    # 9) Integer variables that DO NOT appear in a nonlinear objective or a nonlinear constraint
    #
    # Yes, nonlinear variables are broken into continuous/discrete, but linear
    # variables are partitioned into continuous, binary, and integer.
    #
    # https://cfwebprod.sandia.gov/cfdocs/CompResearch/docs/nlwrite20051130.pdf
    # https://ampl.com/REFS/hooking2.pdf
    #
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
    # "the first nlvb variables appear nonlinearly." Then, the switch on
    # nlvo > nlvc determines whether the next block of variables are the ones
    # that appear in the objective only, or the constraints only.
    #
    # Here, for example, is the relevant code from Couenne:
    # https://github.com/coin-or/Couenne/blob/683c5b305d78a009d59268a4bca01e0ad75ebf02/src/readnl/readnl.cpp#L76-L87
    #
    # Essentially, what that means is if !(nlvo > nlvc), then swap 3-4 for 5-6 in
    # the variable order.
    if !nlmodel.f.is_linear
        for x in nlmodel.f.variables
            nlmodel.x[x].in_nonlinear_objective = true
        end
        for x in nlmodel.f.nonlinear_terms
            if x isa MOI.VariableIndex
                nlmodel.x[x].in_nonlinear_objective = true
            end
        end
    end
    for con in nlmodel.g
        for x in con.expr.variables
            nlmodel.x[x].in_nonlinear_objective = true
        end
        for x in con.expr.nonlinear_terms
            if x isa MOI.VariableIndex
                nlmodel.x[x].in_nonlinear_constraint = true
            end
        end
    end
    types = nlmodel.types
    for (x, v) in nlmodel.x
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
    order_i = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    nlvc = length(types[3]) + length(types[4])
    nlvo = length(types[5]) + length(types[6])
    if !(nlvo > nlvc)
        order_i[3], order_i[4], order_i[5], order_i[6] = 5, 6, 3, 4
    end
    n = 0
    for i in order_i, x in types[i]
        nlmodel.x[x].order = n
        n += 1
    end
    copy!(
        nlmodel.order,
        sort!(collect(keys(nlmodel.x)); by = x -> nlmodel.x[x].order),
    )
    return nlmodel
end

_set_to_bounds(set::MOI.Interval) = (0, set.lower, set.upper)
_set_to_bounds(set::MOI.LessThan) = (1, -Inf, set.upper)
_set_to_bounds(set::MOI.GreaterThan) = (2, set.lower, Inf)
_set_to_bounds(set::MOI.EqualTo) = (4, set.value, set.value)

function _process_constraint(nlmodel::_NLModel, model, F, S)
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(model, MOI.ConstraintFunction(), ci)
        s = MOI.get(model, MOI.ConstraintSet(), ci)
        op, l, u = _set_to_bounds(s)
        con = _NLConstraint(l, u, op, _NLExpr(f))
        if con.expr.is_linear
            push!(nlmodel.h, con)
        else
            push!(nlmodel.g, con)
        end
    end
    return
end

function _process_constraint(
    nlmodel::_NLModel,
    model,
    F::Type{MOI.SingleVariable},
    S,
)
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(model, MOI.ConstraintFunction(), ci)
        s = MOI.get(model, MOI.ConstraintSet(), ci)
        _, l, u = _set_to_bounds(s)
        if l > -Inf
            nlmodel.x[f.variable].lower = l
        end
        if u < Inf
            nlmodel.x[f.variable].upper = u
        end
    end
    return
end

function _process_constraint(
    nlmodel::_NLModel,
    model,
    F::Type{MOI.SingleVariable},
    S::Union{Type{MOI.ZeroOne},Type{MOI.Integer}},
)
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
        f = MOI.get(model, MOI.ConstraintFunction(), ci)
        nlmodel.x[f.variable].type = S == MOI.ZeroOne ? _BINARY : _INTEGER
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

function _write_nlexpr(io::IO, expr::_NLExpr, nlmodel::_NLModel)
    # If the expression is linear, just write out the constant term.
    if expr.is_linear || length(expr.nonlinear_terms) == 0
        _write_term(io, expr.constant, nlmodel)
        return
    end
    # If the nonlinear terms are a summation, we can stick our constant on the
    # end, otherwise, prepend a binary addition of (+ constant terms).
    if !iszero(expr.constant)
        if expr.nonlinear_terms[1] == OPSUMLIST
            expr.nonlinear_terms[2] += 1
            push!(expr.nonlinear_terms, expr.constant)
        else
            pushfirst!(expr.nonlinear_terms, expr.constant)
            pushfirst!(expr.nonlinear_terms, OPPLUS)
        end
    end
    last_nary = false
    for term in expr.nonlinear_terms
        if last_nary
            @assert term isa Int
            println(io, term)
            last_nary = false
        else
            _write_term(io, term, nlmodel)
            last_nary = _is_nary(term)
        end
    end
    return
end

function _write_linear_block(io::IO, expr::_NLExpr, nlmodel::_NLModel)
    elements = map(zip(expr.coefficients, expr.variables)) do (c, x)
        return (c, nlmodel.x[x].order)
    end
    for (c, x) in sort!(elements; by = i -> i[2])
        println(io, x, " ", _str(c))
    end
    return
end

function Base.write(io::IO, nlmodel::_NLModel)
    # ==========================================================================
    # Header
    # Line 1: Always the same
    println(io, "g3 1 1 0")

    # Line 2: vars, constraints, objectives, ranges, eqns, logical constraints
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
    n_nlcon = length(nlmodel.g)
    println(io, " ", n_nlcon, " ", nlmodel.f.is_linear ? 0 : 1)

    # Line 4: network constraints: nonlinear, linear
    println(io, " 0 0")

    # Line 5: nonlinear vars in constraints, objectives, both
    nlvb = length(nlmodel.types[1]) + length(nlmodel.types[2])
    nlvc = nlvb + length(nlmodel.types[3]) + length(nlmodel.types[4])
    nlvo = nlvb + length(nlmodel.types[5]) + length(nlmodel.types[6])
    println(io, " ", nlvc, " ", nlvo, " ", nlvb)

    # Line 6: linear network variables; functions; arith, flags
    # `flags` is set to 1 to get suffixes in .sol file.
    println(io, " 0 0 0 1")

    # # Line 7: discrete variables: binary, integer, nonlinear (b,c,o)
    nbv = length(nlmodel.types[8])
    niv = length(nlmodel.types[9])
    nl_both = length(nlmodel.types[2])
    nl_cons = length(nlmodel.types[4])
    nl_obj = length(nlmodel.types[6])
    println(io, " ", nbv, " ", niv, " ", nl_both, " ", nl_cons, " ", nl_obj)

    # # Line 8: nonzeros in Jacobian, gradients
    nnz_jacobian = 0
    for g in nlmodel.g
        nnz_jacobian += length(g.expr.coefficients)
    end
    for h in nlmodel.h
        nnz_jacobian += length(h.expr.coefficients)
    end
    println(io, " ", nnz_jacobian, " ", length(nlmodel.f.coefficients))

    # Line 9: max name lengths: constraints, variables
    println(io, " 0 0")

    # Line 10: common exprs: b,c,o,c1,o1
    println(io, " 0 0 0 0 0")
    # ==========================================================================
    # Constraints
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
    println(io, "O0 ", nlmodel.sense == MOI.MAX_SENSE ? "1" : "0")
    _write_nlexpr(io, nlmodel.f, nlmodel)
    # ==========================================================================
    # VariablePrimalStart
    println(io, "x", length(nlmodel.x))
    for (i, x) in enumerate(nlmodel.order)
        start = nlmodel.x[x].start
        println(io, i - 1, " ", start === nothing ? 0 : _str(start))
    end
    # ==========================================================================
    # Constraint bounds
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
            c = h.expr.constant
            if h.opcode == 0
                println(io, " ", _str(h.lower - c), " ", _str(h.upper - c))
            elseif h.opcode == 1
                println(io, " ", _str(h.upper - c))
            elseif h.opcode == 2
                println(io, " ", _str(h.lower - c))
            else
                @assert h.opcode == 4
                println(io, " ", _str(h.lower - c))
            end
        end
    end
    # ==========================================================================
    # Variable bounds
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
    if any(x -> nlmodel.x[x].jacobian_count > 0, keys(nlmodel.x))
        println(io, "k", length(nlmodel.x) - 1)
        total = 0
        for i in 1:length(nlmodel.order)-1
            total += nlmodel.x[nlmodel.order[i]].jacobian_count
            println(io, total)
        end
        for (i, g) in enumerate(nlmodel.g)
            println(io, "J", i - 1, " ", length(g.expr.coefficients))
            _write_linear_block(io, g.expr, nlmodel)
        end
        for (i, h) in enumerate(nlmodel.h)
            println(io, "J", i - 1 + n_nlcon, " ", length(h.expr.coefficients))
            _write_linear_block(io, h.expr, nlmodel)
        end
    end
    # ==========================================================================
    # Gradient block
    if nlmodel.f.is_linear && length(nlmodel.f.coefficients) > 0
        println(io, "G0 ", length(nlmodel.f.coefficients))
        _write_linear_block(io, nlmodel.f, nlmodel)
    end
    return nlmodel
end
