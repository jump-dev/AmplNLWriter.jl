using JuMP, FactCheck, AmplNLWriter

## Solve test problem with sind and cosd functions
 #
 #  min   (7 - (3*cosd(x1) + 5*cosd(x2)))^2 + (0 - (3*sind(x1) + 5*sind(x2)))^2
 #  s.t.  x1, x2 continuous
 #
 #  The optimal objective value is 0
 ##

# Allow resolving the model from multiple starts after NLP changes in JuMP 0.12
EnableNLPResolve()

if !isdefined(:solver); solver = CouenneNLSolver(); end

m = Model(solver=solver)
@variable(m, x[1:2])

@NLobjective(m, Min, (7 - (3*cosd(x[1]) + 5*cosd(x[2])))^2 + (0 - (3*sind(x[1]) + 5*sind(x[2])))^2)

context("example: jump_nltrig") do
    setvalue(x[1], 30)
    setvalue(x[2], -50)
    @fact solve(m) --> :Optimal
    @fact getvalue(x)[:] --> roughly([38.21321, -21.78678], 1e-5)
    @fact getobjectivevalue(m) --> roughly(0.0, 1e-5)
    # Now try from the other side
    setvalue(x[1], -30)
    setvalue(x[2], 50)
    @fact solve(m) --> :Optimal
    @fact getvalue(x)[:] --> roughly([-38.21321, 21.78678], 1e-5)
    @fact getobjectivevalue(m) --> roughly(0.0, 1e-5)
end
