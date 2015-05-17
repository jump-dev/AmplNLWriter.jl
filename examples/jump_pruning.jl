using JuMP, FactCheck, AmplNLWriter, CoinOptServices

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

m = Model(solver=AmplNLSolver(CoinOptServices.bonmin))
@defVar(m, x[1:2] >= 0)

@setNLObjective(m, Max, x[1]^2 * x[2]^2)
@addNLConstraint(m, x[1] * x[2] <= 20)
@addNLConstraint(m, x[1] + x[2] <= 40)
@addNLConstraint(m, x[1] * x[2] + x[1] + x[2] <= 60)
@addNLConstraint(m, x[1] + x[1] * x[2] + x[2] <= 60)
@addNLConstraint(m, x[1] * x[2] + x[1] + x[2] <= 60)
@addNLConstraint(m, x[1] * x[2] - x[1] - x[2] <= 0)
@addNLConstraint(m, x[2] - x[1] * x[2] + x[1] <= 60)
@addNLConstraint(m, x[2] - x[1] + x[1] * x[2] <= 0)

facts("[jump_pruning] Test optimal solutions") do
    @fact solve(m) => :Optimal
    @fact getObjectiveValue(m) => roughly(400, 1e-5)
end
