facts("[nl_linearity] check simplification of formulae") do
    context("ifelse") do
        # First term is true, we should choose `then`
        expr = :(ifelse(1 > 0, x[1] ^ 2, x[2] + 1))
        lin_expr = NL.LinearityExpr(expr)
        @fact NL.convert_formula(lin_expr.c) => :(x[1] ^ 2)
        @fact lin_expr.linearity => :nonlinear

        # First term is false, we should choose `else`
        expr = :(ifelse(1 < 0, x[1] ^ 2, x[2] + 1))
        lin_expr = NL.LinearityExpr(expr)
        @fact NL.convert_formula(lin_expr.c) => :(x[2] + 1)
        @fact lin_expr.linearity => :linear

        # First term isn't constant, we can't simplify
        expr = :(ifelse(1 > x[1], x[1] ^ 2, x[2] + 1))
        lin_expr = NL.LinearityExpr(expr)
        @fact NL.convert_formula(lin_expr.c) => expr
        @fact lin_expr.linearity => :nonlinear
    end
end
