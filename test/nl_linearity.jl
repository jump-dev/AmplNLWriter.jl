using AmplNLWriter
using Test

@testset "[nl_linearity] check simplification of formulae" begin
    @testset "ifelse" begin
        # First term is true, we should choose `then`
        expr = :(ifelse(1 > 0, x[1] ^ 2, x[2] + 1))
        lin_expr = AmplNLWriter.LinearityExpr(expr)
        @test AmplNLWriter.convert_formula(lin_expr.c) == :(x[1] ^ 2)
        @test lin_expr.linearity == :nonlinear

        # First term is false, we should choose `else`
        expr = :(ifelse(1 < 0, x[1] ^ 2, x[2] + 1))
        lin_expr = AmplNLWriter.LinearityExpr(expr)
        @test AmplNLWriter.convert_formula(lin_expr.c) == :(x[2] + 1)
        @test lin_expr.linearity == :linear

        # First term isn't constant, we can't simplify
        expr = :(ifelse(1 > x[1], x[1] ^ 2, x[2] + 1))
        lin_expr = AmplNLWriter.LinearityExpr(expr)
        @test AmplNLWriter.convert_formula(lin_expr.c) == expr
        @test lin_expr.linearity == :nonlinear
    end
end
