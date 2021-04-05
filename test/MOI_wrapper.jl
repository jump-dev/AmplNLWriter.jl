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

function optimizer(solver_cmd)
    return MOI.Bridges.full_bridge_optimizer(
        AmplNLWriter.Optimizer(solver_cmd, ["print_level = 0"]),
        Float64,
    )
end

function test_name(solver_cmd)
    @test sprint(
        show,
        AmplNLWriter.Optimizer(solver_cmd, ["print_level = 0"]),
    ) == "An AmplNLWriter model"
end

function test_unittest(solver_cmd)
    return MOI.Test.unittest(
        optimizer(solver_cmd),
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

function test_contlinear(solver_cmd)
    return MOI.Test.contlineartest(
        optimizer(solver_cmd),
        CONFIG,
        String["linear15",],
    )
end

function test_contlquadratic(solver_cmd)
    return MOI.Test.contquadratictest(optimizer(solver_cmd), CONFIG)
end

function test_solver_name(solver_cmd)
    @test MOI.get(optimizer(solver_cmd), MOI.SolverName()) == "AmplNLWriter"
end

function test_abstractoptimizer(solver_cmd)
    @test optimizer(solver_cmd) isa MOI.AbstractOptimizer
end

function test_defaultobjective(solver_cmd)
    return MOI.Test.default_objective_test(optimizer(solver_cmd))
end

function test_default_status_test(solver_cmd)
    return MOI.Test.default_status_test(optimizer(solver_cmd))
end

function test_nametest(solver_cmd)
    return MOI.Test.nametest(optimizer(solver_cmd))
end

function test_validtest(solver_cmd)
    return MOI.Test.validtest(optimizer(solver_cmd))
end

function test_emptytest(solver_cmd)
    return MOI.Test.emptytest(optimizer(solver_cmd))
end

function test_orderedindices(solver_cmd)
    return MOI.Test.orderedindicestest(optimizer(solver_cmd))
end

function test_copytest(solver_cmd)
    return MOI.Test.copytest(
        optimizer(solver_cmd),
        MOI.Bridges.full_bridge_optimizer(
            AmplNLWriter.Optimizer(solver_cmd),
            Float64,
        ),
    )
end

function test_nlptest(solver_cmd)
    return MOI.Test.nlptest(optimizer(solver_cmd), CONFIG)
end

function test_bad_string(::Any)
    model = AmplNLWriter.Optimizer("bad_solver")
    x = MOI.add_variable(model)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OTHER_ERROR
    @test occursin("IOError", MOI.get(model, MOI.RawStatusString()))
end

function runtests(solver_cmd)
    for name in names(@__MODULE__; all = true)
        if !startswith("$(name)", "test_")
            continue
        end
        @testset "$(name)" begin
            getfield(@__MODULE__, name)(solver_cmd)
        end
    end
end

end

TestMOIWrapper.runtests(SOLVER_CMD)
