using AmplNLWriter, Ipopt

import MathOptInterface
const MOI = MathOptInterface
const MOIT = MOI.Test

const OPTIMIZER = AmplNLWriter.Optimizer(Ipopt.amplexe, ["print_level = 0"])

const CONFIG = MOIT.TestConfig(
    atol = 1e-4, rtol = 1e-4, optimal_status = MOI.LOCALLY_SOLVED,
    infeas_certificates = false, duals = false
)

@testset "Unit Tests" begin
    MOIT.unittest(OPTIMIZER, CONFIG, [
        "solve_objbound_edge_cases",  # ObjectiveBound not implemented
        "solve_integer_edge_cases",  # Ipopt doesn't handle integer
        "solve_affine_deletion_edge_cases",  # VectorAffineFunction
        # It seems that the AMPL NL reader declares NL files with no objective
        # and no constraints as corrupt, even if they have variable bounds. Yuk.
        "solve_blank_obj"
    ])
end

@testset "Linear tests" begin
    MOIT.contlineartest(OPTIMIZER, CONFIG, [
        "linear7", "linear15"  # VectorAffineFunction
    ])
end

@testset "Quadratic tests" begin
    MOIT.contquadratictest(OPTIMIZER, CONFIG, [
        "qcp1"  # VectorAffineFunction
    ])
end

@testset "ModelLike tests" begin
    @test MOI.get(OPTIMIZER, MOI.SolverName()) == "AmplNLWriter"
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
        # Requires VectorOfVariables
        # MOIT.emptytest(OPTIMIZER)
    end
    @testset "orderedindicestest" begin
        MOIT.orderedindicestest(OPTIMIZER)
    end
    @testset "copytest" begin
        # Requires VectorOfVariables
        # MOIT.copytest(OPTIMIZER, AmplNLWriter.Optimizer(Ipopt.amplexe))
    end
end

@testset "MOI NLP tests" begin
    # Requires ExprGraph in MOI tests
    # MOIT.nlptest(OPTIMIZER, CONFIG)
end
