### ============================================================================
### Opcodes, and their AMPL <-> Julia conversions.
### ============================================================================

include("opcode.jl")

"""
    _JULIA_TO_AMPL

This dictionary is manualy curated, based on the list of opcodes in `opcode.jl`.

The goal is to map Julia functions to their AMPL opcode equivalent.

Sometimes, there is ambiguity, such as the `:+`, which Julia uses for unary,
binary, and n-ary addition, while AMPL doesn't support unary addition, uses
OPPLUS for binary, and OPSUMLIST for n-ary. In these cases, introduce a
different symbol to disambiguate them in the context of this dictionary, and add
logic to `_process_expr!` to rewrite the Julia expression.

Commented out lines are opcodes supported by AMPL that don't have a clear Julia
equivalent. If you can think of one, feel free to add it. But then go and make
similar changes to `_AMPL_TO_JULIA` and `_NARY_OPCODES`.
"""
const _JULIA_TO_AMPL = Dict{Symbol,Int}(
    :+ => OPPLUS,  # binary-plus
    :- => OPMINUS,
    :* => OPMULT,
    :/ => OPDIV,
    :rem => OPREM,
    :^ => OPPOW,
    # OPLESS = 6
    :min => MINLIST,  # n-ary
    :max => MAXLIST,  # n-ary
    # FLOOR = 13
    # CEIL = 14
    :abs => ABS,
    :neg => OPUMINUS,
    :|| => OPOR,
    :&& => OPAND,
    :(<) => LT,
    :(<=) => LE,
    :(==) => EQ,
    :(>=) => GE,
    :(>) => GT,
    :(!=) => NE,
    :(!) => OPNOT,
    :ifelse => OPIFnl,
    :tanh => OP_tanh,
    :tan => OP_tan,
    :sqrt => OP_sqrt,
    :sinh => OP_sinh,
    :sin => OP_sin,
    :log10 => OP_log10,
    :log => OP_log,
    :exp => OP_exp,
    :cosh => OP_cosh,
    :cos => OP_cos,
    :atanh => OP_atanh,
    # OP_atan2 = 48,
    :atan => OP_atan,
    :asinh => OP_asinh,
    :asin => OP_asin,
    :acosh => OP_acosh,
    :acos => OP_acos,
    :sum => OPSUMLIST,  # n-ary plus
    # OPintDIV = 55
    # OPprecision = 56
    # OPround = 57
    # OPtrunc = 58
    # OPCOUNT = 59
    # OPNUMBEROF = 60
    # OPNUMBEROFs = 61
    # OPATLEAST = 62
    # OPATMOST = 63
    # OPPLTERM = 64
    # OPIFSYM = 65
    # OPEXACTLY = 66
    # OPNOTATLEAST = 67
    # OPNOTATMOST = 68
    # OPNOTEXACTLY = 69
    # ANDLIST = 70
    # ORLIST = 71
    # OPIMPELSE = 72
    # OP_IFF = 73
    # OPALLDIFF = 74
    # OPSOMESAME = 75
    # OP1POW = 76
    # OP2POW = 77
    # OPCPOW = 78
    # OPFUNCALL = 79
    # OPNUM = 80
    # OPHOL = 81
    # OPVARVAL = 82
    # N_OPS = 83
)

"""
    _AMPL_TO_JULIA

This dictionary is manualy curated, based on the list of supported opcodes
`_JULIA_TO_AMPL`.

The goal is to map AMPL opcodes to their Julia equivalents. In addition, we need
to know the arity of each opcode.

If the opcode is an n-ary function, use `-1`.
"""
const _AMPL_TO_JULIA = Dict{Int,Tuple{Int,Function}}(
    OPPLUS => (2, +),
    OPMINUS => (2, -),
    OPMULT => (2, *),
    OPDIV => (2, /),
    OPREM => (2, rem),
    OPPOW => (2, ^),
    # OPLESS = 6
    MINLIST => (-1, minimum),
    MAXLIST => (-1, maximum),
    # FLOOR = 13
    # CEIL = 14
    ABS => (1, abs),
    OPUMINUS => (1, -),
    OPOR => (2, |),
    OPAND => (2, &),
    LT => (2, <),
    LE => (2, <=),
    EQ => (2, ==),
    GE => (2, >=),
    GT => (2, >),
    NE => (2, !=),
    OPNOT => (1, !),
    OPIFnl => (3, ifelse),
    OP_tanh => (1, tanh),
    OP_tan => (1, tan),
    OP_sqrt => (1, sqrt),
    OP_sinh => (1, sinh),
    OP_sin => (1, sin),
    OP_log10 => (1, log10),
    OP_log => (1, log),
    OP_exp => (1, exp),
    OP_cosh => (1, cosh),
    OP_cos => (1, cos),
    OP_atanh => (1, atanh),
    # OP_atan2 = 48,
    OP_atan => (1, atan),
    OP_asinh => (1, asinh),
    OP_asin => (1, asin),
    OP_acosh => (1, acosh),
    OP_acos => (1, acos),
    OPSUMLIST => (-1, sum),
    # OPintDIV = 55
    # OPprecision = 56
    # OPround = 57
    # OPtrunc = 58
    # OPCOUNT = 59
    # OPNUMBEROF = 60
    # OPNUMBEROFs = 61
    # OPATLEAST = 62
    # OPATMOST = 63
    # OPPLTERM = 64
    # OPIFSYM = 65
    # OPEXACTLY = 66
    # OPNOTATLEAST = 67
    # OPNOTATMOST = 68
    # OPNOTEXACTLY = 69
    # ANDLIST = 70
    # ORLIST = 71
    # OPIMPELSE = 72
    # OP_IFF = 73
    # OPALLDIFF = 74
    # OPSOMESAME = 75
    # OP1POW = 76
    # OP2POW = 77
    # OPCPOW = 78
    # OPFUNCALL = 79
    # OPNUM = 80
    # OPHOL = 81
    # OPVARVAL = 82
    # N_OPS = 83
)

"""
    _NARY_OPCODES

A manually curated list of n-ary opcodes, taken from Table 8 of "Writing .nl
files."

Not all of these are implemented. See `_REV_OPCODES` for more detail.
"""
const _NARY_OPCODES = Set([
    MINLIST,
    MAXLIST,
    OPSUMLIST,
    OPCOUNT,
    OPNUMBEROF,
    OPNUMBEROFs,
    ANDLIST,
    ORLIST,
    OPALLDIFF,
])

"""
    _UNARY_SPECIAL_CASES

This dictionary defines a set of unary functions that are special-cased. They
don't exist in the NL file format, but they may be called from Julia, and
they can easily be converted into NL-compatible expressions.

If you have a new unary-function that you want to support, add it here.
"""
const _UNARY_SPECIAL_CASES = Dict(
    :cbrt => (x) -> :($x^(1 / 3)),
    :abs2 => (x) -> :($x^2),
    :inv => (x) -> :(1 / $x),
    :log2 => (x) -> :(log($x) / log(2)),
    :log1p => (x) -> :(log(1 + $x)),
    :exp2 => (x) -> :(2^$x),
    :expm1 => (x) -> :(exp($x) - 1),
    :sec => (x) -> :(1 / cos($x)),
    :csc => (x) -> :(1 / sin($x)),
    :cot => (x) -> :(1 / tan($x)),
    :asec => (x) -> :(acos(1 / $x)),
    :acsc => (x) -> :(asin(1 / $x)),
    :acot => (x) -> :(pi / 2 - atan($x)),
    :sind => (x) -> :(sin(pi / 180 * $x)),
    :cosd => (x) -> :(cos(pi / 180 * $x)),
    :tand => (x) -> :(tan(pi / 180 * $x)),
    :secd => (x) -> :(1 / cos(pi / 180 * $x)),
    :cscd => (x) -> :(1 / sin(pi / 180 * $x)),
    :cotd => (x) -> :(1 / tan(pi / 180 * $x)),
    :asind => (x) -> :(asin($x) * 180 / pi),
    :acosd => (x) -> :(acos($x) * 180 / pi),
    :atand => (x) -> :(atan($x) * 180 / pi),
    :asecd => (x) -> :(acos(1 / $x) * 180 / pi),
    :acscd => (x) -> :(asin(1 / $x) * 180 / pi),
    :acotd => (x) -> :((pi / 2 - atan($x)) * 180 / pi),
    :sech => (x) -> :(1 / cosh($x)),
    :csch => (x) -> :(1 / sinh($x)),
    :coth => (x) -> :(1 / tanh($x)),
    :asech => (x) -> :(acosh(1 / $x)),
    :acsch => (x) -> :(asinh(1 / $x)),
    :acoth => (x) -> :(atanh(1 / $x)),
)

### ============================================================================
### Nonlinear expressions
### ============================================================================

# TODO(odow): This type isn't great. We should experiment with something that is
# type-stable, like
#
# @enum(_NLType, _INTEGER, _DOUBLE, _VARIABLE)
# struct _NLTerm
#     type::_NLType
#     data::Int64
# end
# _NLTerm(x::Int) = _NLTerm(_INTEGER, x)
# _NLTerm(x::Float64) = _NLTerm(_DOUBLE, reinterpret(Int64, x))
# _NLTerm(x::MOI.VariableIndex) = _NLTerm(_VARIABLE, x.value)
# function _value(x::_NLTerm)
#     if x.type == _INTEGER
#         return x.data
#     elseif x.type == _DOUBLE
#         return reinterpret(Float64, x.data)
#     else
#         @assert x.type == _VARIABLE
#         return MOI.VariableIndex(x.data)
#     end
# end

const _NLTerm = Union{Int,Float64,MOI.VariableIndex}

struct _NLExpr
    is_linear::Bool
    nonlinear_terms::Vector{_NLTerm}
    linear_terms::Dict{MOI.VariableIndex,Float64}
    constant::Float64
end

function Base.:(==)(x::_NLExpr, y::_NLExpr)
    return x.is_linear == y.is_linear &&
           x.nonlinear_terms == y.nonlinear_terms &&
           x.linear_terms == y.linear_terms &&
           x.constant == y.constant
end

_NLExpr(x::MOI.VariableIndex) = _NLExpr(true, _NLTerm[], Dict(x => 1.0), 0.0)

_NLExpr(x::MOI.SingleVariable) = _NLExpr(x.variable)

function _add_or_set(dict, key, value)
    if haskey(dict, key)
        dict[key] += value
    else
        dict[key] = value
    end
    return
end

function _NLExpr(x::MOI.ScalarAffineFunction)
    linear = Dict{MOI.VariableIndex,Float64}()
    for (i, term) in enumerate(x.terms)
        _add_or_set(linear, term.variable_index, term.coefficient)
    end
    return _NLExpr(true, _NLTerm[], linear, x.constant)
end

function _NLExpr(x::MOI.ScalarQuadraticFunction)
    linear = Dict{MOI.VariableIndex,Float64}()
    for (i, term) in enumerate(x.affine_terms)
        _add_or_set(linear, term.variable_index, term.coefficient)
    end
    terms = _NLTerm[]
    N = length(x.quadratic_terms)
    if N == 0 || N == 1
        # If there are 0 or 1 terms, no need for an addition node.
    elseif N == 2
        # If there are two terms, use binary addition.
        push!(terms, OPPLUS)
    elseif N > 2
        # If there are more, use n-ary addition.
        push!(terms, OPSUMLIST)
        push!(terms, N)
    end
    for term in x.quadratic_terms
        coefficient = term.coefficient
        # MOI defines quadratic as 1/2 x' Q x :(
        if term.variable_index_1 == term.variable_index_2
            coefficient *= 0.5
        end
        # Optimization: no need for the OPMULT if the coefficient is 1.
        if !isone(coefficient)
            push!(terms, OPMULT)
            push!(terms, coefficient)
        end
        push!(terms, OPMULT)
        push!(terms, term.variable_index_1)
        push!(terms, term.variable_index_2)
        # For the Jacobian sparsity patterns, we need to add a linear term, even
        # if the variable only appears nonlinearly.
        _add_or_set(linear, term.variable_index_1, 0.0)
        _add_or_set(linear, term.variable_index_2, 0.0)
    end
    return _NLExpr(false, terms, linear, x.constant)
end

function _NLExpr(expr::Expr)
    nlexpr = _NLExpr(false, _NLTerm[], Dict{MOI.VariableIndex,Float64}(), 0.0)
    _process_expr!(nlexpr, expr)
    return nlexpr
end

function _process_expr!(expr::_NLExpr, arg::Real)
    return push!(expr.nonlinear_terms, Float64(arg))
end

function _process_expr!(expr::_NLExpr, arg::MOI.VariableIndex)
    _add_or_set(expr.linear_terms, arg, 0.0)
    return push!(expr.nonlinear_terms, arg)
end

# TODO(odow): these process_expr! functions use recursion. For large models,
# this may exceed the stack. At some point, we may have to rewrite this to not
# use recursion.
function _process_expr!(expr::_NLExpr, arg::Expr)
    if arg.head == :call
        f = get(_UNARY_SPECIAL_CASES, arg.args[1], nothing)
        if f !== nothing
            if length(arg.args) != 2
                error("Uncorrect number of arguments to $(arg.args[1]).")
            end
            # Some unary-functions are special cased. See the associated comment
            # next to the definition of _UNARY_SPECIAL_CASES.
            _process_expr!(expr, f(arg.args[2]))
        else
            _process_expr!(expr, arg.args)
        end
    elseif arg.head == :ref
        _process_expr!(expr, arg.args[2])
    elseif arg == :()
        return  # Some evalators return a null objective of `:()`.
    else
        error("Unsupported expression: $(arg)")
    end
    return
end

function _process_expr!(expr::_NLExpr, args::Vector{Any})
    op = first(args)
    N = length(args) - 1
    # Before processing the arguments, do some re-writing.
    if op == :+
        if N == 1  # +x, so we can just drop the op and process the args.
            return _process_expr!(expr, args[2])
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
    # Now convert the Julia expression into an _NLExpr.
    opcode = get(_JULIA_TO_AMPL, op, nothing)
    if opcode === nothing
        error("Unsupported operation $(op)")
    end
    push!(expr.nonlinear_terms, opcode)
    if opcode in _NARY_OPCODES
        push!(expr.nonlinear_terms, N)
    end
    for i in 1:N
        _process_expr!(expr, args[i+1])
    end
    return
end

### ============================================================================
### Evaluate nonlinear expressions
### ============================================================================

function _evaluate(expr::_NLExpr, x::Dict{MOI.VariableIndex,Float64})
    y = expr.constant
    for (v, c) in expr.linear_terms
        y += c * x[v]
    end
    if length(expr.nonlinear_terms) > 0
        ret, n = _evaluate(expr.nonlinear_terms[1], expr.nonlinear_terms, x, 1)
        @assert n == length(expr.nonlinear_terms) + 1
        y += ret
    end
    return y
end

function _evaluate(
    head::MOI.VariableIndex,
    ::Vector{_NLTerm},
    x::Dict{MOI.VariableIndex,Float64},
    head_i::Int,
)::Tuple{Float64,Int}
    return x[head], head_i + 1
end

function _evaluate(
    head::Float64,
    ::Vector{_NLTerm},
    ::Dict{MOI.VariableIndex,Float64},
    head_i::Int,
)::Tuple{Float64,Int}
    return head, head_i + 1
end

function _evaluate(
    head::Int,
    terms::Vector{_NLTerm},
    x::Dict{MOI.VariableIndex,Float64},
    head_i::Int,
)::Tuple{Float64,Int}
    N, f = _AMPL_TO_JULIA[head]
    is_nary = (N == -1)
    head_i += 1
    if is_nary
        N = terms[head_i]::Int
        head_i += 1
    end
    args = Vector{Float64}(undef, N)
    for n in 1:N
        args[n], head_i = _evaluate(terms[head_i], terms, x, head_i)
    end
    return is_nary ? f(args) : f(args...), head_i
end

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
    function _VariableInfo(model::Optimizer, x::MOI.VariableIndex)
        start = MOI.get(model, MOI.VariablePrimalStart(), x)
        return new(-Inf, Inf, _CONTINUOUS, start, 0, false, false, 0)
    end
end

struct _NLModel
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
    _NLModel(model::Optimizer)

Given a `MOI.FileFormats.NL.Model` object, return an `_NLModel` describing:

    sense f(x)
    s.t.  l_g <= g(x) <= u_g
          l_h <= h(x) <= u_h
          l_x <=   x  <= u_x
          x_cat_i ∈ {:Bin, :Int},

where `g` are nonlinear functions and `h` are linear.
"""
function _NLModel(model::Optimizer)
    # Initialize the NLP block.
    nlp_block = MOI.get(model, MOI.NLPBlock())
    MOI.initialize(nlp_block.evaluator, [:ExprGraph])
    # Objective function.
    objective = if nlp_block.has_objective
        _NLExpr(MOI.objective_expr(nlp_block.evaluator))
    else
        F = MOI.get(model, MOI.ObjectiveFunctionType())
        obj = MOI.get(model, MOI.ObjectiveFunction{F}())
        _NLExpr(obj)
    end
    # Nonlinear constraints
    g = [
        _NLConstraint(MOI.constraint_expr(nlp_block.evaluator, i), bound)
        for (i, bound) in enumerate(nlp_block.constraint_bounds)
    ]
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
    # Now deal with the normal MOI constraints.
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        _process_constraint(nlmodel, model, F, S)
    end
    # Correct bounds of binary variables. Mainly because AMPL doesn't have the
    # concept of binary nonlinear variables, but it does have binary linear
    # variables! How annoying.
    for (x, v) in nlmodel.x
        if v.type == _BINARY
            v.lower = max(0.0, v.lower)
            v.upper = min(1.0, v.upper)
        end
    end
    # Jacobian counts. The zero terms for nonlinear constraints should have
    # been added when the expression was constructed.
    for g in nlmodel.g, v in keys(g.expr.linear_terms)
        nlmodel.x[v].jacobian_count += 1
    end
    for h in nlmodel.h, v in keys(h.expr.linear_terms)
        nlmodel.x[v].jacobian_count += 1
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
    if !nlmodel.f.is_linear
        for x in keys(nlmodel.f.linear_terms)
            nlmodel.x[x].in_nonlinear_objective = true
        end
        for x in nlmodel.f.nonlinear_terms
            if x isa MOI.VariableIndex
                nlmodel.x[x].in_nonlinear_objective = true
            end
        end
    end
    for con in nlmodel.g
        for x in keys(con.expr.linear_terms)
            nlmodel.x[x].in_nonlinear_constraint = true
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
    order_i = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    nlvc = length(types[3]) + length(types[4])
    nlvo = length(types[5]) + length(types[6])
    if !(nlvo > nlvc)
        order_i[3], order_i[4], order_i[5], order_i[6] = 5, 6, 3, 4
    end
    # Now we can order the variables.
    n = 1
    for i in order_i, x in types[i]
        nlmodel.x[x].order = n - 1  # 0-indexed.
        nlmodel.order[n] = x
        n += 1
    end
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

function _write_linear_block(io::IO, expr::_NLExpr, nlmodel::_NLModel)
    elements = [(c, nlmodel.x[v].order) for (v, c) in expr.linear_terms]
    for (c, x) in sort!(elements; by = i -> i[2])
        println(io, x, " ", _str(c))
    end
    return
end

function Base.write(io::IO, nlmodel::_NLModel)
    # ==========================================================================
    # Header
    # Line 1: Always the same
    # Notes:
    #  * I think there are magic bytes used by AMPL internally for stuff.
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
    #  * We don't support linear constraints. I don't know how they are
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
        start = nlmodel.x[x].start
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
    #  * You don't need to write out the `k` entry for the last variable,
    #    because it can be inferred from the total number of elements in the
    #    Jacobian as given in the header.
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
    #  * You only need to write this ot if there are linear terms in the
    #    objective.
    if nnz_gradient > 0
        println(io, "G0 ", nnz_gradient)
        _write_linear_block(io, nlmodel.f, nlmodel)
    end
    return nlmodel
end
