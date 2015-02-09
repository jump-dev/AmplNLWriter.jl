type LinearityExpr
  c
  linearity::Symbol
  coeff::Float64
end

LinearityExpr(c, linearity) = LinearityExpr(c, linearity, 1)

Base.print(io::IO, c::LinearityExpr) = print(io::IO, "($(c.c),$(c.linearity))")
Base.show(io::IO, c::LinearityExpr) = print(io::IO, "($(c.c),$(c.linearity))")

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
          length(filter((c) -> check_linearity(:linear, c), args)) > 1
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
      elseif c.args[2].linearity == :linear
        if c.args[3].c == 1
          linearity = :linear
        else
          linearity = :nonlinear
        end
      else
        linearity = c.args[2].linearity
      end
    else
      if check_for_linearity(:linear, args) ||
          check_for_linearity(:nonlinear, args)
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

get_expr(c) = c
function get_expr(c::Expr)
  for i in 2:length(c.args)
    c.args[i] = get_expr(c.args[i].c)
  end
  return c
end

function pull_up_constants(c::LinearityExpr)
  if c.linearity == :const
    c.c = eval(get_expr(c.c))
  elseif isa(c.c, Expr) && c.c.head == :call
    for i in 2:length(c.c.args)
      c.c.args[i] = pull_up_constants(c.c.args[i])
    end
  end
  return c
end

function prune_linear_terms!(c::LinearityExpr, lin_constr::Dict{Int64, Float64},
                             constant::Float64=0.0, negative_tree::Bool=false)
  if c.linearity != :nonlinear
    constant = add_linear_tree!(c, lin_constr, constant, negative_tree)
    c = LinearityExpr(:(0), :const)
    return true, c, constant
  else
    expr = c.c
    if expr.head == :call
      if expr.args[1] == :+
        n = length(expr.args)
        pruned = falses(n - 1)
        for i in 2:n
          pruned[i - 1], expr.args[i], constant = prune_linear_terms!(
              expr.args[i], lin_constr, constant)
        end
        if sum(!pruned) > 1
          inds = vcat([1], [2:n][!pruned])
          c.c.args = expr.args[inds]
        else
          c = expr.args[findfirst(!pruned) + 1]
        end
      elseif expr.args[1] == :-
        if length(expr.args) == 3
          pruned_first, expr.args[2], constant = prune_linear_terms!(
              expr.args[2], lin_constr, constant)
          pruned_second, expr.args[3], constant = prune_linear_terms!(
              expr.args[3], lin_constr, constant, true)
          if pruned_first
            new_expr = Expr(:call, :-, expr.args[3])
            c = LinearityExpr(new_expr, :nonlinear)
          elseif pruned_second
            c = expr.args[2]
          end
        end
      end
    end
    return false, c, constant
  end
end

function add_linear_tree!(c::LinearityExpr, lin_constr::Dict{Int64, Float64},
                          constant::Float64=0.0, negative_tree::Bool=false)
  c = collate_linear_terms(c)
  negative_tree && negate(c)
  constant = add_tree_to_constr!(c, lin_constr, constant)
  return constant
end

function collate_linear_terms(c::LinearityExpr)
  if isa(c.c, Expr) && c.c.head == :call
    for i in 2:length(c.c.args)
      c.c.args[i] = collate_linear_terms(c.c.args[i])
    end
  end
  if c.linearity == :linear && isa(c.c, Expr) && c.c.head == :call
    func = c.c.args[1]
    if func == :-
      if length(c.c.args) == 2
        c = negate(c.c.args[2])
      else
        c.c.args[3] = negate(c.c.args[3])
        c.c.args[1] = :+
      end
    elseif func == :*
      if c.c.args[2].linearity == :const
        c = multiply(c.c.args[3], c.c.args[2].c)
      else
        c = multiply(c.c.args[2], c.c.args[3].c)
      end
    elseif func == :/
      c = multiply(c.c.args[2], 1 / c.c.args[3])
    elseif func == :^
      c = c.c.args[2]
    end
  end
  return c
end

negate(c::LinearityExpr) = multiply(c::LinearityExpr, -1)
function multiply(c::LinearityExpr, a::Real)
  if isa(c.c, Expr) && c.c.head == :call
    @assert c.c.args[1] == :+
    for i in 2:length(c.c.args)
      c.c.args[i] = multiply(c.c.args[i], a)
    end
  elseif c.linearity == :const
    c.c *= a
  else
    c.coeff *= a
  end
  return c
end

function add_tree_to_constr!(c::LinearityExpr, lin_constr::Dict{Int64, Float64},
                             constant::Float64)
  if isa(c.c, Expr) && c.c.head == :call
    @assert c.c.args[1] == :+
    for i in 2:length(c.c.args)
      constant = add_tree_to_constr!(c.c.args[i], lin_constr, constant)
    end
  elseif c.linearity == :const
    constant += c.c
  else
    lin_constr[c.c.args[2]] += c.coeff
  end
  return constant
end
