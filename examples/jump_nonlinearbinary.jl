using JuMP, Base.Test, AmplNLWriter

## Solve test problem with non-linear binary variables
 #
 #  min   100 * (x2 - (0.5 + x1) ^ 2) ^ 2 + (1 - x1) ^ 2
 #  s.t.  x1, x2 binary
 #
 #  The solution is (0, 0).
 ##

# solver = AmplNLSolver(Ipopt.amplexe, ["print_level=0"])

@testset "example: jump_nonlinearbinary" begin
    m = Model(solver=solver)
    @variable(m, x[1:2], Bin)

    # Set some non-binary bounds on x1 and x2. These should be ignored.
    # The optimal solution if x is Int is (1, 2) which is allowed by these bounds
    setupperbound(x[1], 2)
    setupperbound(x[2], 2)

    @NLobjective(m, Min, 100*(x[2] - (0.5 + x[1])^2)^2 + (1 - x[1])^2)

    @test solve(m) == :Optimal

    if getsolvername(solver) == "ipopt"
        # Ipopt solves the relaxation
        @test isapprox(getvalue(x), [0.501245, 1.0], atol=1e-6)
        @test isapprox(getobjectivevalue(m), 0.249377, atol=1e-6)
    else
        @test getvalue(x)[:] == [0.0, 0.0]
        @test getobjectivevalue(m) == 7.25
    end
end
