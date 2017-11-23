import AmplNLWriter

@testset "[nl_convert] check special conversion cases" begin
    special_cases = [:cbrt, :abs2, :inv, :log2, :log1p, :exp2, :expm1, :sec,
                     :csc, :cot, :sind, :cosd, :tand, :asind, :acosd, :atand,
                     :secd, :cscd, :cotd, :sech, :csch, :coth, :asech, :acsch]
    for func in special_cases
        x = rand()
        expr = Expr(:call, func, x)
        @test isapprox(eval(AmplNLWriter.convert_formula(expr)), eval(expr), atol=1e-6)
    end
    # These functions need input >1
    for func in [:acoth, :asec, :acsc, :acot, :asecd, :acscd, :acotd]
        x = rand() + 1
        expr = Expr(:call, func, x)
        @test isapprox(eval(AmplNLWriter.convert_formula(expr)),
               eval(expr), atol=1e-6)
    end
end

@testset "[nl_convert] check numeric values" begin
    x = rand()
    @test AmplNLWriter.convert_formula(:($x)) == :($x)
    x = -rand()
    @test AmplNLWriter.convert_formula(:($x)) == :($x)
end

@testset "[nl_convert] check unary, binary and n-ary plus" begin
    expr = :(+(1))
    @test AmplNLWriter.convert_formula(expr) == :(1)
    expr = :(1 + 2)
    @test AmplNLWriter.convert_formula(expr) == :(1 + 2)
    expr = :(1 + 2 + 3)
    @test AmplNLWriter.convert_formula(expr) == :(sum(1, 2, 3))
end

@testset "[nl_convert] check unary, binary and n-ary minus" begin
    expr = :(- x)
    @test AmplNLWriter.convert_formula(expr) == :(neg(x))
    expr = :(x - y)
    @test AmplNLWriter.convert_formula(expr) == :(x - y)
    expr = :(x - y - z)
    @test AmplNLWriter.convert_formula(expr) == :((x - y) - z)
end

@testset "[nl_convert] check n-ary multiplication" begin
    expr = :(x * y * z)
    @test AmplNLWriter.convert_formula(expr) == :(x * (y * z))
end

@testset "[nl_convert] check comparison expansion" begin
    expr = :(1 < 2 < 3)
    @test AmplNLWriter.convert_formula(expr) == :(1 < 2 && 2 < 3)
    expr = :(1 < 2 < 3 < 4)
    @test AmplNLWriter.convert_formula(expr) == :((1 < 2 && 2 < 3) && 3 < 4)
end
