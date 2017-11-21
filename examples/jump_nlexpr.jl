using JuMP, Base.Test, AmplNLWriter

# Example testing basic use of NLExpr with AmplNLWriter.jl

if !isdefined(:solver); solver = IpoptNLSolver(); end

@testset "example: jump_nlexpr" begin
    m = Model(solver=solver)

    n = 30
    l = -ones(n); l[1] = 0
    u = ones(n)
    @variable(m, l[i] <= x[i=1:n] <= u[i])
    @NLexpression(m, f1, x[1])
    @NLexpression(m, g, 1 + 9 * sum(x[j] ^ 2 for j = 2:n) / (n - 1))
    @NLexpression(m, h, 1 - (f1 / g) ^ 2)
    @NLexpression(m, f2, g * h)

    setvalue(x[1], 1)
    setvalue(x[2:n], zeros(n - 1))
    @NLobjective(m, :Min, f2)

    @test solve(m) == :Optimal
    @test isapprox(getvalue(x[1]), 1.0, atol=1e-5)
    @test isapprox(getvalue(x[2:end]), zeros(n - 1), atol=1e-5)
    @test isapprox(getvalue(f1), 1.0, atol=1e-5)
    @test isapprox(getvalue(f2), 0.0, atol=1e-5)
    @test isapprox(getvalue(g), 1.0, atol=1e-5)
    @test isapprox(getvalue(h), 0.0, atol=1e-5)
    @test isapprox(getobjectivevalue(m), 0.0, atol=1e-5)
end
