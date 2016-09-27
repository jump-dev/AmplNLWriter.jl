using JuMP, FactCheck, AmplNLWriter

# Example with no objective (#50)

if !isdefined(:solver); solver = BonminNLSolver(); end

m = Model(solver=solver)
@variable(m, 0 <= yp <= 1, Int)
@variable(m, 0 <= l <= 1000.0)
@variable(m, 0 <= f <= 1000.0)
@NLconstraint(m, .087 * l >= f ^ 2)
@constraint(m, l <= yp * 1000.0)
@objective(m, Min, 5)

context("example: jump_no_obj") do
    @fact solve(m) --> :Optimal
    @fact getobjectivevalue(m) --> 5
end
