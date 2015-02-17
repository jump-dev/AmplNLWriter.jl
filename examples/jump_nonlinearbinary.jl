using JuMP, FactCheck, NL

## Solve test problem with non-linear binary variables
 #
 #  min   100 * (x2 - (0.5 + x1) ^ 2) ^ 2 + (1 - x1) ^ 2
 #  s.t.  x1, x2 binary
 #
 #  The solution is (0, 0).
 ##

m = Model(solver=NLSolver())
@defVar(m, x[1:2], Bin)

@setNLObjective(m, Min, 100*(x[2] - (0.5 + x[1])^2)^2 + (1 - x[1])^2)
solve(m)

facts("[jump_nonlinearbinary] Test optimal solutions") do
  @fact solve(m) => :Optimal
  @fact getValue(x)[:] => [0.0, 0.0]
  @fact getObjectiveValue(m) => 7.25
end
