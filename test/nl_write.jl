facts("[nl_write] Temp file handling") do
    # Turn on debug mode so files persist
    old_debug = AmplNLWriter.debug
    AmplNLWriter.setdebug(true)

    filename = "test"
    filepath = joinpath(AmplNLWriter.solverdata_dir, filename)
    probfile = "$filepath.nl"
    solfile = "$filepath.sol"
    AmplNLWriter.clean_solverdata()

    context("all temp files deleted successfully") do
        @fact length(readdir(AmplNLWriter.solverdata_dir)) --> 1
    end

    solver = BonminNLSolver(filename=filename)
    m = Model(solver=solver)
    @variable(m, x >= 0)
    @objective(m, Min, x)
    solve(m)

    context("temp files present after solve in debug mode") do
        @fact length(readdir(AmplNLWriter.solverdata_dir)) --> 3
    end
    context("temp files used custom name") do
        @fact isfile(probfile) --> true
        @fact isfile(solfile) --> true
    end

    # Reset debug mode and clean up
    AmplNLWriter.setdebug(old_debug)
    AmplNLWriter.clean_solverdata()
end
