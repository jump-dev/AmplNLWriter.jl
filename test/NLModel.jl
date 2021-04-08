module TestNLModel

using AmplNLWriter
const NL = AmplNLWriter

using MathOptInterface
const MOI = MathOptInterface

using Test

function _test_expr(
    expr::NL._NLExpr,
    nonlinear_terms,
    variables,
    coefficients,
    constant,
)
    @test expr.is_linear == (length(nonlinear_terms) == 0)
    @test expr.nonlinear_terms == nonlinear_terms
    @test expr.variables == variables
    @test expr.coefficients == coefficients
    @test expr.constant == constant
    return
end
_test_expr(x, args...) = _test_expr(NL._NLExpr(x), args...)
_test_linear(x, args...) = _test_expr(x, NL._NLTerm[], args...)
function _test_nonlinear(x, terms)
    return _test_expr(x, terms, MOI.VariableIndex[], Float64[], 0.0)
end

function test_nlexpr_singlevariable()
    x = MOI.VariableIndex(1)
    return _test_linear(MOI.SingleVariable(x), [x], [1.0], 0.0)
end

function test_nlexpr_scalaraffine()
    x = MOI.VariableIndex.(1:3)
    f = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, x), 4.0)
    return _test_linear(f, x, [1.0, 1.0, 1.0], 4.0)
end

function test_nlexpr_scalarquadratic()
    x = MOI.VariableIndex(1)
    f = MOI.ScalarQuadraticFunction(
        [MOI.ScalarAffineTerm(1.1, x)],
        [MOI.ScalarQuadraticTerm(2.0, x, x)],
        3.0,
    )
    terms = [NL.OPMULT, x, x]
    return _test_expr(f, terms, [x], [1.1], 3.0)
end

function test_nlexpr_unary_addition()
    x = MOI.VariableIndex(1)
    return _test_nonlinear(:(+$x), [x])
end

function test_nlexpr_binary_addition()
    x = MOI.VariableIndex(1)
    y = MOI.VariableIndex(2)
    return _test_nonlinear(:($x + $y), [NL.OPPLUS, x, y])
end

function test_nlexpr_nary_addition()
    x = MOI.VariableIndex(1)
    y = MOI.VariableIndex(2)
    return _test_nonlinear(:($x + $y + 1.0), [NL.OPSUMLIST, 3, x, y, 1.0])
end

function test_nlexpr_unary_subtraction()
    x = MOI.VariableIndex(1)
    return _test_nonlinear(:(-$x), [NL.OPUMINUS, x])
end

function test_nlexpr_nary_multiplication()
    x = MOI.VariableIndex(1)
    return _test_nonlinear(:($x * $x * 2.0), [NL.OPMULT, x, NL.OPMULT, x, 2.0])
end

function test_nlexpr_unary_specialcase()
    x = MOI.VariableIndex(1)
    return _test_nonlinear(:(cbrt($x)), [NL.OPPOW, x, NL.OPDIV, 1, 3])
end

function test_nlexpr_unsupportedoperation()
    x = MOI.VariableIndex(1)
    err = ErrorException("Unsupported operation foo")
    @test_throws err NL._NLExpr(:(foo($x)))
    return
end

function test_nlexpr_unsupportedexpression()
    x = MOI.VariableIndex(1)
    expr = :(1 <= $x <= 2)
    err = ErrorException("Unsupported expression: $(expr)")
    @test_throws err NL._NLExpr(expr)
    return
end

function test_nlexpr_ref()
    x = MOI.VariableIndex(1)
    return _test_nonlinear(:(x[$x]), [x])
end

function test_nlconstraint_interval()
    x = MOI.VariableIndex(1)
    expr = :(1 <= $x <= 2)
    con = NL._NLConstraint(expr)
    @test con.lower == 1
    @test con.upper == 2
    @test con.opcode == 0
    @test con.expr == NL._NLExpr(expr.args[3])
end

function test_nlconstraint_lessthan()
    x = MOI.VariableIndex(1)
    expr = :($x <= 2)
    con = NL._NLConstraint(expr)
    @test con.lower == -Inf
    @test con.upper == 2
    @test con.opcode == 1
    @test con.expr == NL._NLExpr(expr.args[2])
end

function test_nlconstraint_greaterthan()
    x = MOI.VariableIndex(1)
    expr = :($x >= 2)
    con = NL._NLConstraint(expr)
    @test con.lower == 2
    @test con.upper == Inf
    @test con.opcode == 2
    @test con.expr == NL._NLExpr(expr.args[2])
end

function test_nlconstraint_equalto()
    x = MOI.VariableIndex(1)
    expr = :($x == 2)
    con = NL._NLConstraint(expr)
    @test con.lower == 2
    @test con.upper == 2
    @test con.opcode == 4
    @test con.expr == NL._NLExpr(expr.args[2])
end

function test_nlmodel_hs071()
    model = NL.Optimizer()
    v = MOI.add_variables(model, 4)
    l = [1.1, 1.2, 1.3, 1.4]
    u = [5.1, 5.2, 5.3, 5.4]
    start = [2.1, 2.2, 2.3, 2.4]
    MOI.add_constraint.(model, MOI.SingleVariable.(v), MOI.GreaterThan.(l))
    MOI.add_constraint.(model, MOI.SingleVariable.(v), MOI.LessThan.(u))
    MOI.set.(model, MOI.VariablePrimalStart(), v, start)
    lb, ub = [25.0, 40.0], [Inf, 40.0]
    evaluator = MOI.Test.HS071(true)
    block_data = MOI.NLPBlockData(MOI.NLPBoundsPair.(lb, ub), evaluator, true)
    MOI.set(model, MOI.NLPBlock(), block_data)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    n = NL._NLModel(model)
    @test n.sense == MOI.MIN_SENSE
    @test n.f == NL._NLExpr(MOI.objective_expr(evaluator))
    _test_nonlinear(
        n.g[1].expr,
        [NL.OPMULT, v[1], NL.OPMULT, v[2], NL.OPMULT, v[3], v[4]],
    )
    @test n.g[1].lower == 25.0
    @test n.g[1].upper == Inf
    @test n.g[1].opcode == 2
    _test_nonlinear(
        n.g[2].expr,
        [
            NL.OPSUMLIST,
            4,
            NL.OPPOW,
            v[1],
            2,
            NL.OPPOW,
            v[2],
            2,
            NL.OPPOW,
            v[3],
            2,
            NL.OPPOW,
            v[4],
            2,
        ],
    )
    @test n.g[2].lower == 40.0
    @test n.g[2].upper == 40.0
    @test n.g[2].opcode == 4
    @test length(n.h) == 0
    for i in 1:4
        @test n.x[v[i]].lower == l[i]
        @test n.x[v[i]].upper == u[i]
        @test n.x[v[i]].type == NL._CONTINUOUS
        @test n.x[v[i]].jacobian_count == 0
        @test n.x[v[i]].in_nonlinear_constraint
        @test n.x[v[i]].in_nonlinear_objective
        @test 0 <= n.x[v[i]].order <= 3
    end
    @test length(n.types[1]) == 4
    @test sprint(write, model) == """
    g3 1 1 0
     4 2 1 0 1 0
     2 1
     0 0
     4 4 4
     0 0 0 1
     0 0 0 0 0
     0 0
     0 0
     0 0 0 0 0
    C0
    o2
    v3
    o2
    v1
    o2
    v2
    v0
    C1
    o54
    4
    o5
    v3
    o2
    o5
    v1
    o2
    o5
    v2
    o2
    o5
    v0
    o2
    O0 0
    o0
    o2
    v3
    o2
    v0
    o54
    3
    v3
    v1
    v2
    v2
    x4
    0 2.4
    1 2.2
    2 2.3
    3 2.1
    r
    2 25
    4 40
    b
    0 1.4 5.4
    0 1.2 5.2
    0 1.3 5.3
    0 1.1 5.1
    """
    return
end

function test_nlmodel_hs071_linear_obj()
    model = NL.Optimizer()
    v = MOI.add_variables(model, 4)
    l = [1.1, 1.2, 1.3, 1.4]
    u = [5.1, 5.2, 5.3, 5.4]
    start = [2.1, 2.2, 2.3, 2.4]
    MOI.add_constraint.(model, MOI.SingleVariable.(v), MOI.GreaterThan.(l))
    MOI.add_constraint.(model, MOI.SingleVariable.(v), MOI.LessThan.(u))
    MOI.add_constraint(model, MOI.SingleVariable(v[2]), MOI.ZeroOne())
    MOI.add_constraint(model, MOI.SingleVariable(v[3]), MOI.Integer())
    MOI.set.(model, MOI.VariablePrimalStart(), v, start)
    lb, ub = [25.0, 40.0], [Inf, 40.0]
    evaluator = MOI.Test.HS071(true)
    block_data = MOI.NLPBlockData(MOI.NLPBoundsPair.(lb, ub), evaluator, false)
    MOI.set(model, MOI.NLPBlock(), block_data)
    f = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(l, v), 2.0)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    n = NL._NLModel(model)
    @test n.sense == MOI.MAX_SENSE
    @test n.f == NL._NLExpr(f)
    _test_nonlinear(
        n.g[1].expr,
        [NL.OPMULT, v[1], NL.OPMULT, v[2], NL.OPMULT, v[3], v[4]],
    )
    @test n.g[1].lower == 25.0
    @test n.g[1].upper == Inf
    @test n.g[1].opcode == 2
    _test_nonlinear(
        n.g[2].expr,
        [
            NL.OPSUMLIST,
            4,
            NL.OPPOW,
            v[1],
            2,
            NL.OPPOW,
            v[2],
            2,
            NL.OPPOW,
            v[3],
            2,
            NL.OPPOW,
            v[4],
            2,
        ],
    )
    @test n.g[2].lower == 40.0
    @test n.g[2].upper == 40.0
    @test n.g[2].opcode == 4
    @test length(n.h) == 0
    types = [NL._CONTINUOUS, NL._BINARY, NL._INTEGER, NL._CONTINUOUS]
    u[2] = 1.0
    for i in 1:4
        @test n.x[v[i]].lower == l[i]
        @test n.x[v[i]].upper == u[i]
        @test n.x[v[i]].type == types[i]
        @test n.x[v[i]].jacobian_count == 0
        @test n.x[v[i]].in_nonlinear_constraint
        @test !n.x[v[i]].in_nonlinear_objective
        @test 0 <= n.x[v[i]].order <= 3
    end
    @test length(n.types[3]) == 2
    @test length(n.types[4]) == 2
    @test v[1] in n.types[3]
    @test v[2] in n.types[4]
    @test v[3] in n.types[4]
    @test v[4] in n.types[3]
    @test sprint(write, model) == """
    g3 1 1 0
     4 2 1 0 1 0
     2 0
     0 0
     4 0 0
     0 0 0 1
     0 0 0 2 0
     0 4
     0 0
     0 0 0 0 0
    C0
    o2
    v1
    o2
    v2
    o2
    v3
    v0
    C1
    o54
    4
    o5
    v1
    o2
    o5
    v2
    o2
    o5
    v3
    o2
    o5
    v0
    o2
    O0 1
    n2
    x4
    0 2.4
    1 2.1
    2 2.2
    3 2.3
    r
    2 25
    4 40
    b
    0 1.4 5.4
    0 1.1 5.1
    0 1.2 1
    0 1.3 5.3
    G0 4
    0 1.4
    1 1.1
    2 1.2
    3 1.3
    """
    return
end

function test_nlmodel_linear_quadratic()
    model = NL.Optimizer()
    x = MOI.add_variables(model, 4)
    MOI.add_constraint.(model, MOI.SingleVariable.(x), MOI.GreaterThan(0.0))
    MOI.add_constraint.(model, MOI.SingleVariable.(x), MOI.LessThan(2.0))
    MOI.add_constraint(model, MOI.SingleVariable(x[2]), MOI.ZeroOne())
    MOI.add_constraint(model, MOI.SingleVariable(x[3]), MOI.Integer())
    f = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, x[2:4]), 2.0)
    g = MOI.ScalarQuadraticFunction(
        [MOI.ScalarAffineTerm(1.0, x[1])],
        [MOI.ScalarQuadraticTerm(2.0, x[1], x[2])],
        3.0,
    )
    h = MOI.ScalarQuadraticFunction(
        [MOI.ScalarAffineTerm(1.0, x[3])],
        [MOI.ScalarQuadraticTerm(1.0, x[1], x[2])],
        0.0,
    )
    MOI.add_constraint(model, f, MOI.Interval(1.0, 10.0))
    MOI.add_constraint(model, g, MOI.LessThan(5.0))
    MOI.set(model, MOI.ObjectiveFunction{typeof(h)}(), h)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    n = NL._NLModel(model)
    @test n.sense == MOI.MAX_SENSE
    @test n.f == NL._NLExpr(h)
    terms = [NL.OPMULT, 2.0, NL.OPMULT, x[1], x[2]]
    _test_expr(n.g[1].expr, terms, [x[1]], [1.0], 3.0)
    @test n.g[1].opcode == 1
    @test n.g[1].lower == -Inf
    @test n.g[1].upper == 5.0
    @test n.h[1].expr == NL._NLExpr(f)
    @test n.h[1].opcode == 0
    @test n.h[1].lower == 1.0
    @test n.h[1].upper == 10.0
    @test n.types[1] == [x[1]]  # Continuous in both
    @test n.types[2] == [x[2]]  # Discrete in both
    @test n.types[6] == [x[3]]  # Discrete in objective only
    @test n.types[7] == [x[4]]  # Continuous in linear

    @test sprint(write, model) == """
    g3 1 1 0
     4 2 1 1 0 0
     1 1
     0 0
     2 3 2
     0 0 0 1
     0 0 1 0 1
     4 1
     0 0
     0 0 0 0 0
    C0
    o0
    n3
    o2
    n2
    o2
    v0
    v1
    C1
    n2
    O0 1
    o2
    v0
    v1
    x4
    0 0
    1 0
    2 0
    3 0
    r
    1 5
    0 -1 8
    b
    0 0 2
    0 0 1
    0 0 2
    0 0 2
    k3
    1
    2
    3
    J0 1
    0 1
    J1 3
    1 1
    2 1
    3 1
    """
    return
end

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
end

end

TestNLModel.runtests()
