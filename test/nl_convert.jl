facts("[nl_convert] check special conversion cases") do
  special_cases = [:cbrt, :abs2, :inv, :log2, :log1p, :exp2, :expm1, :sec, :csc,
                   :cot, :secd, :cscd, :cotd, :sech, :csch, :coth, :asech,
                   :acsch]
  for func in special_cases
    x = rand()
    expr = Expr(:call, func, x)
    @fact eval(convert_formula(expr)) => roughly(eval(expr), 1e-6)
  end
  # These functions need input >1
  for func in [:acoth, :asec, :acsc, :acot, :asecd, :acscd, :acotd]
    x = rand() + 1
    expr = Expr(:call, func, x)
    @fact eval(convert_formula(expr)) => roughly(eval(expr), 1e-6)
  end
end

facts("[nl_convert] check numeric values") do
  x = rand()
  @fact convert_formula(:($x)) => :($x)
  x = -rand()
  @fact convert_formula(:($x)) => :(-$(-x))
end

facts("[nl_convert] check binary and n-ary plus") do
  expr = :(1 + 2)
  @fact convert_formula(expr) => :(1 + 2)
  expr = :(1 + 2 + 3)
  @fact convert_formula(expr) => :(sum(1, 2, 3))
end

facts("[nl_convert] check unary, binary and n-ary minus") do
  expr = :(- x)
  @fact convert_formula(expr) => :(neg(x))
  expr = :(x - y)
  @fact convert_formula(expr) => :(x - y)
  expr = :(x - y - z)
  @fact convert_formula(expr) => :((x - y) - z)
end
