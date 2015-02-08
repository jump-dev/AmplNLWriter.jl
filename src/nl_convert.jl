convert_formula(c) = c

# Convert any negative number to Expr with :-
convert_formula(c::Real) = c < 0 ? :(- $(-c)) : c

function convert_formula(c::Expr)
  if c.head == :comparison
    for i in 2:length(c.args)
      c.args[i] = convert_formula(c.args[i])
    end

  elseif c.head == :call
    for i in 2:length(c.args)
      c.args[i] = convert_formula(c.args[i])
    end

    op = c.args[1]
    # Distinguish n-ary and binary plus
    if op == :+
      if length(c.args) > 3
        c.args[1] = :sum
      end
    # Distinguish unary and binary minus
    elseif op == :-
      n = length(c.args)
      if n == 2
        c.args[1] = :neg
      end
    # Handle normal conversion cases
    else
      if length(c.args) == 2
        c = get(unary_special_cases, c.args[1],
                (x) -> Expr(:call, c.args[1], x))(c.args[2])
      end
    end
  end
  c
end

const unary_special_cases = Compat.@compat Dict(
:cbrt  => (x) -> :($x ^ (1 / 3)),
:abs2  => (x) -> :($x ^ 2),
:inv   => (x) -> :(1 / $x),
:log2  => (x) -> :(log($x) / log(2)),
:log1p => (x) -> :(log(1 + $x)),
:exp2  => (x) -> :(2 ^ $x),
:expm1 => (x) -> :(exp($x) - 1),

:sec   => (x) -> :(1 / cos($x)),
:csc   => (x) -> :(1 / sin($x)),
:cot   => (x) -> :(1 / tan($x)),

:asec  => (x) -> :(acos(1 / $x)),
:acsc  => (x) -> :(asin(1 / $x)),
:acot  => (x) -> :(pi / 2 - atan($x)),

:secd  => (x) -> :(1 / cos(pi / 180 * $x)),
:cscd  => (x) -> :(1 / sin(pi / 180 * $x)),
:cotd  => (x) -> :(1 / tan(pi / 180 * $x)),

:asecd => (x) -> :(acos(1 / $x) * 180 / pi),
:acscd => (x) -> :(asin(1 / $x) * 180 / pi),
:acotd => (x) -> :((pi / 2 - atan($x)) * 180 / pi),

:sech  => (x) -> :(1 / cosh($x)),
:csch  => (x) -> :(1 / sinh($x)),
:coth  => (x) -> :(1 / tanh($x)),

:asech => (x) -> :(acosh(1 / $x)),
:acsch => (x) -> :(asinh(1 / $x)),
:acoth => (x) -> :(atanh(1 / $x)),
)
