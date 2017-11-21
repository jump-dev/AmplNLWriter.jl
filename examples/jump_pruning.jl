using JuMP, Base.Test, AmplNLWriter

## Solve test problem with lots of expressions to prune
 #
 #  max   x1^2 * x2^2
 #  s.t.  x1 * x2 <= 20
 #        x1 + x2 <= 40
 #        x1 * x2 + x1 + x2 <= 60
 #        x1 + x1 * x2 + x2 <= 60
 #        x1 * x2 + x1 + x2 <= 60
 #        x1 * x2 - x1 - x2 <= 0
 #        x2 - x1 * x2 + x1 <= 60
 #        x2 - x1 + x1 * x2 <= 0
 #        x1, x2 >= 0
 #
 #  The optimal objective value is 400, solutions can vary.
 ##

# solver = AmplNLSolver(Ipopt.amplexe, ["print_level=0"])

@testset "example: jump_pruning" begin
    m = Model(solver=solver)

    @variable(m, x[1:2] >= 0)

    @NLobjective(m, Max, x[1]^2 * x[2]^2)
    @NLconstraint(m, x[1] * x[2] <= 20)
    @NLconstraint(m, x[1] + x[2] <= 40)
    @NLconstraint(m, x[1] * x[2] + x[1] + x[2] <= 60)
    @NLconstraint(m, x[1] + x[1] * x[2] + x[2] <= 60)
    @NLconstraint(m, x[1] * x[2] + x[1] + x[2] <= 60)
    @NLconstraint(m, x[1] * x[2] - x[1] - x[2] <= 0)
    @NLconstraint(m, x[2] - x[1] * x[2] + x[1] <= 60)
    @NLconstraint(m, x[2] - x[1] + x[1] * x[2] <= 0)
    @NLconstraint(m, 0 <= 1.0)

    @test solve(m) == :Optimal
    @test isapprox(getobjectivevalue(m), 400, atol=1e-2)
end
