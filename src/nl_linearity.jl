type LinearityExpr
  c
  linearity::Symbol
end

LinearityExpr(c) = LinearityExpr(c, :unknown)
LinearityExpr(c::Real) = LinearityExpr(c, :const)
function LinearityExpr(c::Expr)
  if c.head == :call
    for i = 2:length(c.args)
      c.args[i] = LinearityExpr(c.args[i])
    end

    linearity = :unknown
    args = c.args[2:end]
    if c.args[1] in [:+, :-]
      if check_for_linearity(:nonlinear, args)
        linearity = :nonlinear
      elseif check_for_linearity(:linear, args)
        linearity = :linear
      else
        linearity = :const
      end
    elseif c.args[1] == :*
      if check_for_linearity(:nonlinear, args) ||
          length(filter(check_linearity, args)) > 1
        linearity = :nonlinear
      elseif check_for_linearity(:linear, args)
        linearity = :linear
      else
        linearity = :const
      end
    elseif c.args[1] == :/
      if c.args[3].linearity != :const
        linearity = :nonlinear
      else
        linearity = c.args[2].linearity
      end
    elseif c.args[1] == :^
      if c.args[3].linearity != :const
        linearity = :nonlinear
      elseif c.args[2].linearity == :linear && c.args[3].c == 1
        linearity = :linear
      else
        linearity = :const
      end
    else
      if !check_for_linearity(:linear, args) ||
          !check_for_linearity(:nonlinear, args)
        linearity = :nonlinear
      else
        linearity = :const
      end
    end
    return LinearityExpr(c, linearity)

  elseif c.head == :ref
    return LinearityExpr(c, :linear)
  end
end

check_linearity(linearity::Symbol, c::LinearityExpr) = c.linearity == linearity

function check_for_linearity(linearity::Symbol, args::Array)
  return !isempty(filter((c) -> check_linearity(linearity, c), args))
end
