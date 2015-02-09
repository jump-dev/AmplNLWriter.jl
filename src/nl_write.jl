function write_nl_file(m::NLMathProgModel)
  f = open(m.probfile, "w")

  write_nl_header(f, m)

  if m.ncon > 0
    write_nl_c_blocks(f, m)
  end

  if m.obj != nothing
    write_nl_o_block(f, m)
  end

  if m.ncon > 0
    write_nl_d_block(f, m)
  end

  write_nl_x_block(f, m)

  if m.ncon > 0
    write_nl_r_block(f, m)
  end

  write_nl_b_block(f, m)

  if m.ncon > 0
    write_nl_k_block(f, m)
    write_nl_j_blocks(f, m)
  end

  if m.obj != nothing
    write_nl_g_block(f, m)
  end

  close(f)
end

function write_nl_header(f, m::NLMathProgModel)
  # Line 1: Always the same
  println(f, "g3 1 1 0")
  # Line 2: vars, constraints, objectives, ranges, eqns, logical constraints
  num_ranges = sum(m.r_codes .!= 4)
  println(f, " $(m.nvar) $(m.ncon) 1 $num_ranges $(m.ncon - num_ranges) 0")
  # Line 3: nonlinear constraints, objectives
  nlc = sum(m.conlinearities .== :Nonlin)
  nlo = int(m.objlinearity == :Nonlin)
  println(f, " $nlc $nlo")
  # Line 4: network constraints: nonlinear, linear
  println(f, " 0 0")
  # Line 5: nonlinear vars in constraints, objectives, both
  nonlinear_obj = m.varlinearities_obj .== :Nonlin
  nonlinear_con = m.varlinearities_con .== :Nonlin
  nonlinear = (nonlinear_con + nonlinear_obj) .> 0
  nonlinear_both = (nonlinear_con + nonlinear_obj) .> 1
  nlvc = sum(nonlinear_con .> 0)
  nlvo = sum(nonlinear_obj .> 0)
  nlvb = sum(nonlinear_both)
  println(f, " $nlvc $nlvo $nlvb")
  # Line 6: linear network variables; functions; arith, flags
  println(f, " 0 0 0 0")
  # Line 7: discrete variables: binary, integer, nonlinear (b,c,o)
  binary = m.vartypes .== :Bin
  integer = m.vartypes .== :Int
  discrete = binary + integer .> 0
  nbv = sum(binary + !nonlinear .> 1)
  niv = sum(integer + !nonlinear .> 1)
  nlvbi = sum(nonlinear_both + discrete .> 1)
  nlvci = sum(nonlinear_con - nonlinear_obj + discrete .> 1)
  nlvoi = sum(nonlinear_obj - nonlinear_con + discrete .> 1)
  println(f, " $nbv $niv $nlvbi $nlvci $nlvoi")
  # Line 8: nonzeros in Jacobian, gradients
  nzc = sum(m.j_counts)
  nzo = length(m.lin_obj)
  println(f, " $nzc $nzo")
  # Line 9: max name lengths: constraints, variables
  println(f, " 0 0")
  # Line 10: common exprs: b,c,o,c1,o1
  println(f, " 0 0 0 0 0")
end

# Nonlinear constraint trees
function write_nl_c_blocks(f, m::NLMathProgModel)
  for index in 0:(m.ncon - 1)
    i = m.c_index_map_rev[index]
    println(f, "C$index")
    write_nl(f, m, m.constrs[i])
  end
end

# Nonlinear objective tree
function write_nl_o_block(f, m::NLMathProgModel)
  println(f, string("O0 ", sense_to_nl[m.sense]))
  write_nl(f, m, m.obj)
end

# Initial dual guesses - unused
function write_nl_d_block(f, m::NLMathProgModel)
  println(f, "d$(m.ncon)")
  for index in 0:(m.ncon - 1)
    i = m.c_index_map_rev[index]
    println(f, "$index 0")
  end
end

# Initial primal guesses
function write_nl_x_block(f, m::NLMathProgModel)
  println(f, "x$(m.nvar)")
  for index in 0:(m.nvar - 1)
    i = m.v_index_map_rev[index]
    println(f, "$index $(m.x_0[i])")
  end
end

# Constraint bounds
function write_nl_r_block(f, m::NLMathProgModel)
  println(f, "r")
  for index in 0:(m.ncon - 1)
    i = m.c_index_map_rev[index]
    lower = m.g_l[i]
    upper = m.g_u[i]
    rel = m.r_codes[i]
    if rel == 0
      println(f, "$rel $lower $upper")
    elseif rel == 1
      println(f, "$rel $upper")
    elseif rel == 2
      println(f, "$rel $lower")
    elseif rel == 3
      println(f, "$rel")
    elseif rel == 4
      println(f, "$rel $lower")
    end
  end
end

# Variable bounds
function write_nl_b_block(f, m::NLMathProgModel)
  println(f, "b")
  for index in 0:(m.nvar - 1)
    i = m.v_index_map_rev[index]
    lower = m.x_l[i]
    upper = m.x_u[i]
    if lower == -Inf
      if upper == Inf
        println(f, "3")
      else
        println(f, "1 $upper")
      end
    else
      if lower == upper
        println(f, "4 $lower")
      elseif upper == Inf
        println(f, "2 $lower")
      else
        println(f, "0 $lower $upper")
      end
    end
  end
end

# Jacobian counts
function write_nl_k_block(f, m::NLMathProgModel)
  println(f, "k$(m.nvar - 1)")
  total = 0
  for index = 0:(m.nvar - 2)
    i = m.v_index_map_rev[index]
    total += m.j_counts[i]
    println(f, total)
  end
end

# Linear constraint expressions
function write_nl_j_blocks(f, m::NLMathProgModel)
  for index in 0:(m.ncon - 1)
    i = m.c_index_map_rev[index]
    println(f, string("J$index ", length(m.lin_constrs[i])))
    for index2 = 0:(m.nvar - 1)
      j = m.v_index_map_rev[index2]
      if j in keys(m.lin_constrs[i])
        println(f, "$index2 $(m.lin_constrs[i][j])")
      end
    end
  end
end

# Linear objective expression
function write_nl_g_block(f, m::NLMathProgModel)
  println(f, string("G0 ", length(m.lin_obj)))
  for index in 0:(m.nvar - 1)
    i = m.v_index_map_rev[index]
    if i in keys(m.lin_obj)
      println(f, "$index $(m.lin_obj[i])")
    end
  end
end

