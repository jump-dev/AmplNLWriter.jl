module TestMOIWrapper

using AmplNLWriter
using Test
import MathOptInterface

const MOI = MathOptInterface

const CONFIG = MOI.Test.TestConfig(
    atol = 1e-4,
    rtol = 1e-4,
    optimal_status = MOI.LOCALLY_SOLVED,
    infeas_certificates = false,
)

function optimizer(path)
    model = AmplNLWriter.Optimizer(path)
    MOI.set(model, MOI.RawParameter("print_level"), 0)
    MOI.set(
        model,
        MOI.RawParameter("option_file_name"),
        joinpath(@__DIR__, "ipopt.opt"),
    )
    return MOI.Utilities.CachingOptimizer(
        MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
        MOI.Bridges.full_bridge_optimizer(
            MOI.Utilities.CachingOptimizer(
                MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
                model,
            ),
            Float64,
        ),
    )
end

function test_show(path)
    @test sprint(show, AmplNLWriter.Optimizer(path)) == "An AMPL (.nl) model"
end

function test_name(path)
    model = AmplNLWriter.Optimizer(path)
    @test MOI.supports(model, MOI.Name())
    MOI.set(model, MOI.Name(), "Foo")
    @test MOI.get(model, MOI.Name()) == "Foo"
end

function test_write_to_file(path)
    model = AmplNLWriter.Optimizer(path)
    MOI.write_to_file(model, "foo.nl")
    @test read("foo.nl", String) == """
    g3 1 1 0
     0 0 1 0 0 0
     0 1
     0 0
     0 0 0
     0 0 0 1
     0 0 0 0 0
     0 0
     0 0
     0 0 0 0 0
    O0 0
    n0
    x0
    b
    """
    rm("foo.nl")
    return
end

function test_unittest(path)
    return MOI.Test.unittest(
        optimizer(path),
        CONFIG,
        [
            # Unsupported attributes:
            "number_threads",
            "silent",
            "solve_objbound_edge_cases",
            "solve_time",
            "time_limit_sec",

            # Ipopt doesn't handle integer
            "solve_integer_edge_cases",
            "solve_zero_one_with_bounds_2",
            "solve_zero_one_with_bounds_3",

            # No support for VectorOfVariables-in-SecondOrderCone
            "delete_soc_variables",
        ],
    )
end

function test_contlinear(path)
    return MOI.Test.contlineartest(optimizer(path), CONFIG)
end

function test_contlquadratic(path)
    return MOI.Test.contquadratictest(optimizer(path), CONFIG)
end

function test_solver_name(path)
    @test MOI.get(optimizer(path), MOI.SolverName()) == "AmplNLWriter"
end

function test_abstractoptimizer(path)
    @test optimizer(path) isa MOI.AbstractOptimizer
end

function test_defaultobjective(path)
    return MOI.Test.default_objective_test(optimizer(path))
end

function test_default_status_test(path)
    return MOI.Test.default_status_test(optimizer(path))
end

function test_nametest(path)
    return MOI.Test.nametest(optimizer(path))
end

function test_validtest(path)
    return MOI.Test.validtest(optimizer(path))
end

function test_emptytest(path)
    return MOI.Test.emptytest(optimizer(path))
end

function test_orderedindices(path)
    return MOI.Test.orderedindicestest(optimizer(path))
end

function test_copytest(path)
    return MOI.Test.copytest(optimizer(path), optimizer(path))
end

function test_nlptest(path)
    return MOI.Test.nlptest(optimizer(path), CONFIG)
end

function test_bad_string(::Any)
    model = optimizer("bad_solver")
    x = MOI.add_variable(model)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OTHER_ERROR
    @test occursin("IOError", MOI.get(model, MOI.RawStatusString()))
end

function test_function_constant_nonzero(path)
    model = optimizer(path)
    x = MOI.add_variable(model)
    f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 1.0)
    MOI.add_constraint(model, f, MOI.GreaterThan(3.0))
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    @test isapprox(MOI.get(model, MOI.VariablePrimal(), x), 2.0, atol = 1e-6)
    @test isapprox(MOI.get(model, MOI.ObjectiveValue()), 3.0, atol = 1e-6)
end

function test_raw_parameter(path)
    model = AmplNLWriter.Optimizer(path)
    attr = MOI.RawParameter("print_level")
    @test MOI.supports(model, attr)
    @test MOI.get(model, attr) === nothing
    MOI.set(model, attr, 0)
    @test MOI.get(model, attr) == 0
end

function test_single_variable_interval_dual(path)
    model = optimizer(path)
    x = MOI.add_variable(model)
    c = MOI.add_constraint(model, MOI.SingleVariable(x), MOI.Interval(0.0, 1.0))
    f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 2.0)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.optimize!(model)
    @test isapprox(MOI.get(model, MOI.ConstraintDual(), c), -1, atol = 1e-6)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    @test isapprox(MOI.get(model, MOI.ConstraintDual(), c), 1, atol = 1e-6)
    return
end

function test_nlpblockdual(path)
    model = optimizer(path)
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
    MOI.optimize!(model)
    dual = MOI.get(model, MOI.NLPBlockDual())
    @test isapprox(dual, [0.1787618002239518, 0.9850008232874167], atol = 1e-6)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.optimize!(model)
    dual = MOI.get(model, MOI.NLPBlockDual())
    @test isapprox(dual, [0.0, -5.008488314902599], atol = 1e-6)
end

function runtests(path)
    for name in names(@__MODULE__; all = true)
        if !startswith("$(name)", "test_")
            continue
        end
        @testset "$(name)" begin
            getfield(@__MODULE__, name)(path)
        end
    end
end

end

if VERSION < v"1.3"
    import Ipopt
    TestMOIWrapper.runtests(Ipopt.amplexe)
else
    import Ipopt_jll
    TestMOIWrapper.runtests(Ipopt_jll.amplexe)
end
