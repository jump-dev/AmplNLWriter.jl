using JuMP, FactCheck, AmplNLWriter

# Example testing basic use of NLExpr with AmplNLWriter.jl

if !isdefined(:solver); solver = IpoptNLSolver(); end

m = Model(solver=solver)

n = 30
l = -ones(n); l[1] = 0
u = ones(n)
@variable(m, l[i] <= x[i=1:n] <= u[i])
@NLexpression(m, f1, x[1])
@NLexpression(m, g, 1 + 9 * sum{x[j] ^ 2, j = 2:n} / (n - 1))
@NLexpression(m, h, 1 - (f1 / g) ^ 2)
@NLexpression(m, f2, g * h)

setvalue(x[1], 1)
setvalue(x[2:n], zeros(n - 1))
@NLobjective(m, :Min, f2)

context("example: jump_nlexpr") do
    @fact solve(m) --> :Optimal
    @fact getvalue(x[1]) --> roughly(1.0, 1e-5)
    @fact getvalue(x[2:end]) --> roughly(zeros(n - 1), 1e-5)
    @fact getvalue(f1) --> roughly(1.0, 1e-5)
    @fact getvalue(f2) --> roughly(0.0, 1e-5)
    @fact getvalue(g) --> roughly(1.0, 1e-5)
    @fact getvalue(h) --> roughly(0.0, 1e-5)
    @fact getobjectivevalue(m) --> roughly(0.0, 1e-5)
end

