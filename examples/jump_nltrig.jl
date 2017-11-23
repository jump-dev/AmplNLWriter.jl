using JuMP, Base.Test, AmplNLWriter

## Solve test problem with sind and cosd functions
 #
 #  min   (7 - (3*cosd(x1) + 5*cosd(x2)))^2 + (0 - (3*sind(x1) + 5*sind(x2)))^2
 #  s.t.  x1, x2 continuous
 #
 #  The optimal objective value is 0
 ##

# solver = AmplNLSolver(Ipopt.amplexe, ["print_level=0"])

@testset "example: jump_nltrig" begin
    m = Model(solver=solver)
    @variable(m, x[1:2])

    @NLobjective(m, Min, (7 - (3*cosd(x[1]) + 5*cosd(x[2])))^2 + (0 - (3*sind(x[1]) + 5*sind(x[2])))^2)

    setvalue(x[1], 30)
    setvalue(x[2], -50)
    @test solve(m) == :Optimal
    @test isapprox(getvalue(x)[:], [38.21321, -21.78678], atol=1e-5)
    @test isapprox(getobjectivevalue(m), 0.0, atol=1e-5)
    # Now try from the other side
    setvalue(x[1], -30)
    setvalue(x[2], 50)
    @test solve(m) == :Optimal
    @test isapprox(getvalue(x)[:], [-38.21321, 21.78678], atol=1e-5)
    @test isapprox(getobjectivevalue(m), 0.0, atol=1e-5)
end
