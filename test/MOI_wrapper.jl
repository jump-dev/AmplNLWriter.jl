using AmplNLWriter
import Ipopt
import MathOptInterface

const MOI = MathOptInterface
const MOIT = MOI.Test

const OPTIMIZER = MOI.Bridges.full_bridge_optimizer(
    AmplNLWriter.Optimizer(Ipopt.amplexe, ["print_level = 0"]),
    Float64
)

@test sprint(
    show,
    AmplNLWriter.Optimizer(Ipopt.amplexe, ["print_level = 0"])
) == "An AmplNLWriter model"

const CONFIG = MOIT.TestConfig(
    atol = 1e-4,
    rtol = 1e-4,
    optimal_status = MOI.LOCALLY_SOLVED,
    infeas_certificates = false,
    duals = false
)

@testset "Unit Tests" begin
    MOIT.unittest(OPTIMIZER, CONFIG, [
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
    ])
end

@testset "Linear tests" begin
    MOIT.contlineartest(OPTIMIZER, CONFIG, String[
        "linear15",
    ])
end

@testset "Quadratic tests" begin
    MOIT.contquadratictest(OPTIMIZER, CONFIG)
end

@testset "ModelLike tests" begin
    @test MOI.get(OPTIMIZER, MOI.SolverName()) == "AmplNLWriter"
    @test OPTIMIZER isa MOI.AbstractOptimizer
    @testset "default_objective_test" begin
         MOIT.default_objective_test(OPTIMIZER)
     end
     @testset "default_status_test" begin
         MOIT.default_status_test(OPTIMIZER)
     end
    @testset "nametest" begin
        MOIT.nametest(OPTIMIZER)
    end
    @testset "validtest" begin
        MOIT.validtest(OPTIMIZER)
    end
    @testset "emptytest" begin
        MOIT.emptytest(OPTIMIZER)
    end
    @testset "orderedindicestest" begin
        MOIT.orderedindicestest(OPTIMIZER)
    end
    @testset "copytest" begin
        MOIT.copytest(
            OPTIMIZER,
            MOI.Bridges.full_bridge_optimizer(
                AmplNLWriter.Optimizer(Ipopt.amplexe),
                Float64
            )
        )
    end
end

@testset "MOI NLP tests" begin
    MOIT.nlptest(OPTIMIZER, CONFIG)
end

@testset "RawStatusString" begin
    model = AmplNLWriter.Optimizer("bad_solver")
    x = MOI.add_variable(model)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OTHER_ERROR
    @test occursin("IOError", MOI.get(model, MOI.RawStatusString()))
end
