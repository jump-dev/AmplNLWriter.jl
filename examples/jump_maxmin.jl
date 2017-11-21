using JuMP, Base.Test, AmplNLWriter

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
@testset "example: maxmin" begin
    m = Model(solver=solver)
    @variable(m, -0.5 <= x <= 0.5, start = 0.25)
    @NLobjective(m, Max, min(x^2, 0.3, x))
    @test solve(m) == :Optimal
    @test isapprox(getobjectivevalue(m), 0.25, atol=1e-2)
    @test isapprox(getvalue(x), 0.5, atol=1e-2)
end

## Solve test problem with simple max functions
 #
 #  min   max( x^2, x )
 #  s.t.  -0.5 <= x <= 0.5
 #
 #  The optimal objective value is 0.
 #      x = 0.
##
@testset "example: minmax" begin
    m = Model(solver=solver)
    @variable(m, -1 <= x <= 1, start=-1)
    @NLobjective(m, Min, max(x^2, x, -1))
    @test solve(m) == :Optimal
    @test isapprox(getobjectivevalue(m), 0, atol=1e-2)
    @test isapprox(getvalue(x), 0, atol=1e-2)
end
