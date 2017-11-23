using FactCheck
import AmplNLWriter

facts("[nl_convert] check special conversion cases") do
    special_cases = [:cbrt, :abs2, :inv, :log2, :log1p, :exp2, :expm1, :sec,
                     :csc, :cot, :sind, :cosd, :tand, :asind, :acosd, :atand,
                     :secd, :cscd, :cotd, :sech, :csch, :coth, :asech, :acsch]
    for func in special_cases
        x = rand()
        expr = Expr(:call, func, x)
        @fact (eval(AmplNLWriter.convert_formula(expr)) -->
               roughly(eval(expr), 1e-6))
    end
    # These functions need input >1
    for func in [:acoth, :asec, :acsc, :acot, :asecd, :acscd, :acotd]
        x = rand() + 1
        expr = Expr(:call, func, x)
        @fact (eval(AmplNLWriter.convert_formula(expr)) -->
               roughly(eval(expr), 1e-6))
    end
end

facts("[nl_convert] check numeric values") do
    x = rand()
    @fact AmplNLWriter.convert_formula(:($x)) --> :($x)
    x = -rand()
    @fact AmplNLWriter.convert_formula(:($x)) --> :($x)
end

facts("[nl_convert] check unary, binary and n-ary plus") do
    expr = :(+(1))
    @fact AmplNLWriter.convert_formula(expr) --> :(1)
    expr = :(1 + 2)
    @fact AmplNLWriter.convert_formula(expr) --> :(1 + 2)
    expr = :(1 + 2 + 3)
    @fact AmplNLWriter.convert_formula(expr) --> :(sum(1, 2, 3))
end

facts("[nl_convert] check unary, binary and n-ary minus") do
    expr = :(- x)
    @fact AmplNLWriter.convert_formula(expr) --> :(neg(x))
    expr = :(x - y)
    @fact AmplNLWriter.convert_formula(expr) --> :(x - y)
    expr = :(x - y - z)
    @fact AmplNLWriter.convert_formula(expr) --> :((x - y) - z)
end

facts("[nl_convert] check n-ary multiplication") do
    expr = :(x * y * z)
    @fact AmplNLWriter.convert_formula(expr) --> :(x * (y * z))
end

facts("[nl_convert] check comparison expansion") do
    expr = :(1 < 2 < 3)
    @fact AmplNLWriter.convert_formula(expr) --> :(1 < 2 && 2 < 3)
    expr = :(1 < 2 < 3 < 4)
    @fact AmplNLWriter.convert_formula(expr) --> :((1 < 2 && 2 < 3) && 3 < 4)
end

facts("[nl_convert] check user defined functions error") do
    m = Model(solver=AmplNLSolver("any_solver"))

    myf(x,y) = (x-1)^2+(y-2)^2
    JuMP.register(m, :myf, 2, myf, autodiff=true)

    @variable(m, x[1:2] >= 0.5)
    @NLobjective(m, Min, myf(x[1], x[2]))

    @fact_throws ErrorException solve(m)

    # clean up temp file
    for file in readdir(AmplNLWriter.solverdata_dir)
        startswith(file, "tmp") && rm(joinpath(AmplNLWriter.solverdata_dir, file))
    end
end
