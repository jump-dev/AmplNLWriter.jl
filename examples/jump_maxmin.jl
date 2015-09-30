using JuMP, FactCheck, AmplNLWriter

if !isdefined(:solver); solver = IpoptNLSolver(); end
# Note min and max not implemented in Couenne

## Solve test problem with simple min functions
 #
 #  max   min( x^2, x )
 #  s.t.  -0.5 <= x <= 0.5
 #
 #  The optimal objective value is 0.25.
 #      x = 0.5
##
context("example: maxmin") do
    m = Model(solver=solver)
    @defVar(m, -0.5 <= x <= 0.5, start = 0.25)
    @setNLObjective(m, Max, min(x^2, 0.3, x))
    @fact solve(m) --> :Optimal
    @fact getObjectiveValue(m) --> roughly(0.25, 1e-2)
    @fact getValue(x) --> roughly(0.5, 1e-2)
end

## Solve test problem with simple max functions
 #
 #  min   max( x^2, x )
 #  s.t.  -0.5 <= x <= 0.5
 #
 #  The optimal objective value is 0.
 #      x = 0.
##
context("example: minmax") do
    m = Model(solver=solver)
    @defVar(m, -1 <= x <= 1, start=-1)
    @setNLObjective(m, Min, max(x^2, x, -1))
    @fact solve(m) --> :Optimal
    @fact getObjectiveValue(m) --> roughly(0, 1e-2)
    @fact getValue(x) --> roughly(0, 1e-2)
end
