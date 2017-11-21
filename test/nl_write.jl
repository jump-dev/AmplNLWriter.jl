@testset "[nl_write] Temp file handling" begin
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

    solver = IpoptNLSolver(filename=filename)#BonminNLSolver(filename=filename)
    m = Model(solver=solver)
    @variable(m, x >= 0)
    @objective(m, Min, x)
    solve(m)

    @testset "temp files present after solve in debug mode" begin
        @test length(readdir(AmplNLWriter.solverdata_dir)) == 3
    end
    @testset "temp files used custom name" begin
        @test isfile(probfile) == true
        @test isfile(solfile) == true
    end

    # Reset debug mode and clean up
    AmplNLWriter.setdebug(old_debug)
    AmplNLWriter.clean_solverdata()
end
