using AmplNLWriter
using Test

function test_temp_file_handling(path)
    # Turn on debug mode so files persist
    old_debug = AmplNLWriter.debug
    AmplNLWriter.setdebug(true)

    filename = "test"
    filepath = joinpath(AmplNLWriter.solverdata_dir, filename)
    probfile = "$filepath.nl"
    solfile = "$filepath.sol"
    AmplNLWriter.clean_solverdata()

    @testset "all temp files deleted successfully" begin
        @test length(readdir(AmplNLWriter.solverdata_dir)) == 1
    end

    MOI = AmplNLWriter.MathOptInterface
    solver = AmplNLWriter.Optimizer(path, filename = filename)
    x = MOI.add_variable(solver)
    MOI.add_constraint(
        solver,
        MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0),
        MOI.GreaterThan(0.0),
    )
    MOI.set(
        solver,
        MOI.ObjectiveFunction{MOI.SingleVariable}(),
        MOI.SingleVariable(x),
    )
    MOI.set(solver, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(solver)

    @testset "temp files present after solve in debug mode" begin
        @test length(readdir(AmplNLWriter.solverdata_dir)) == 3
    end
    @testset "temp files used custom name" begin
        @test isfile(probfile) == true
        @test isfile(solfile) == true
    end

    # Reset debug mode and clean up
    AmplNLWriter.setdebug(old_debug)
    return AmplNLWriter.clean_solverdata()
end

test_temp_file_handling(SOLVER_CMD)
