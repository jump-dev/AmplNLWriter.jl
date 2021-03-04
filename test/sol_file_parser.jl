using AmplNLWriter
using Test

const FILE_80 = """

 Couenne (/home/bgulcan/.julia/v0.6/AmplNLWriter/.solverdata/tmpMSxFvq.nl Mar  6 2018): Infeasible

Options
3
0
1
0
140
0
110
0
objno 0 220
"""

@testset "Test sol file parsing" begin
    @testset "Issue #80" begin
        io = IOBuffer()
        write(io, FILE_80)
        seekstart(io)
        model = AmplNLWriter.AmplNLMathProgModel("", String[], "")
        model.ncon = 140
        model.nvar = 110
        @test !AmplNLWriter.read_sol(io, model)
        @test model.solve_result_num == 220
        @test all(model.solution .=== NaN)
    end
end
