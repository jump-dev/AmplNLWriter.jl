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
    duals = false,
)

function optimizer(path)
    return MOI.Bridges.full_bridge_optimizer(
        AmplNLWriter.Optimizer(path, ["print_level = 0"]),
        Float64,
    )
end

function test_name(path)
    @test sprint(show, AmplNLWriter.Optimizer(path, ["print_level = 0"])) ==
          "An AMPL (.nl) model"
end

function test_unittest(path)
    return MOI.Test.unittest(
        optimizer(path),
        CONFIG,
        [
            # Unsupported attributes:
            "number_threads",
            "raw_status_string",
            "silent",
            "solve_objbound_edge_cases",
            "solve_time",
            "time_limit_sec",

            # Ipopt doesn't handle integer
            "solve_integer_edge_cases",
            "solve_zero_one_with_bounds_2",
            "solve_zero_one_with_bounds_3",

            # It seems that the AMPL NL reader declares NL files with no objective
            # and no constraints as corrupt, even if they have variable bounds. Yuk.
            "solve_blank_obj",

            # No support for VectorOfVariables-in-SecondOrderCone
            "delete_soc_variables",

            # TODO(odow): fix handling of result indices.
            "solve_result_index",
        ],
    )
end

function test_contlinear(path)
    return MOI.Test.contlineartest(optimizer(path), CONFIG, String["linear15",])
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
    return MOI.Test.copytest(
        optimizer(path),
        MOI.Bridges.full_bridge_optimizer(
            AmplNLWriter.Optimizer(path),
            Float64,
        ),
    )
end

function test_nlptest(path)
    return MOI.Test.nlptest(optimizer(path), CONFIG)
end

function test_bad_string(::Any)
    model = AmplNLWriter.Optimizer("bad_solver")
    x = MOI.add_variable(model)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OTHER_ERROR
    @test occursin("IOError", MOI.get(model, MOI.RawStatusString()))
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
