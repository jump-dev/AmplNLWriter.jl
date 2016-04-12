using JuMP, FactCheck, AmplNLWriter

# Example testing basic use of NLExpr with AmplNLWriter.jl

if !isdefined(:solver); solver = IpoptNLSolver(); end

m = Model(solver=solver)

n = 30
l = -ones(n); l[1] = 0
u = ones(n)
@defVar(m, l[i] <= x[i=1:n] <= u[i])
@defNLExpr(m, f1, x[1])
@defNLExpr(m, g, 1 + 9 * sum{x[j] ^ 2, j = 2:n} / (n - 1))
@defNLExpr(m, h, 1 - (f1 / g) ^ 2)
@defNLExpr(m, f2, g * h)

setValue(x[1], 1)
setValue(x[2:n], zeros(n - 1))
@setNLObjective(m, :Min, f2)

context("example: jump_nlexpr") do
    @fact solve(m) --> :Optimal
    @fact getValue(x[1]) --> roughly(1.0, 1e-5)
    @fact getValue(x[2:end]) --> roughly(zeros(n - 1), 1e-5)
    @fact getValue(f1) --> roughly(1.0, 1e-5)
    @fact getValue(f2) --> roughly(0.0, 1e-5)
    @fact getValue(g) --> roughly(1.0, 1e-5)
    @fact getValue(h) --> roughly(0.0, 1e-5)
    @fact getObjectiveValue(m) --> roughly(0.0, 1e-5)
end

