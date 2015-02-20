module NL

using MathProgBase
importall MathProgBase.SolverInterface

import Compat

include("nl_linearity.jl")
include("nl_params.jl")
include("nl_convert.jl")

export NLSolver
immutable NLSolver <: AbstractMathProgSolver
    solver_command::String
    options::Dict{ASCIIString, Any}
end
NLSolver(solver_command) = NLSolver(solver_command, Dict{ASCIIString, Any}())

type NLMathProgModel <: AbstractMathProgModel
    options::Dict{ASCIIString, Any}

    solver_command::String

    x_l::Vector{Float64}
    x_u::Vector{Float64}
    g_l::Vector{Float64}
    g_u::Vector{Float64}

    nvar::Int
    ncon::Int

    obj
    constrs::Array{Any}

    lin_constrs::Array{Dict{Int64, Float64}}
    lin_obj::Dict{Int64, Float64}

    r_codes::Vector{Int64}
    j_counts::Vector{Int64}

    vartypes::Vector{Symbol}
    varlinearities_con::Vector{Symbol}
    varlinearities_obj::Vector{Symbol}
    conlinearities::Vector{Symbol}
    objlinearity::Symbol

    v_index_map::Dict{Int64, Int64}
    v_index_map_rev::Dict{Int64, Int64}
    c_index_map::Dict{Int64, Int64}
    c_index_map_rev::Dict{Int64, Int64}

    sense::Symbol

    x_0::Vector{Float64}

    probfile::String
    solfile::String

    objval::Float64
    solution::Vector{Float64}
    status::Symbol

    d::AbstractNLPEvaluator

    function NLMathProgModel(solver_command::String,
                             options::Dict{ASCIIString, Any})
        new(options,
            solver_command,
            zeros(0),
            zeros(0),
            zeros(0),
            zeros(0),
            0,
            0,
            :(0),
            [],
            Dict{Int64, Float64}[],
            Dict{Int64, Float64}(),
            Int64[],
            Int64[],
            Symbol[],
            Symbol[],
            Symbol[],
            Symbol[],
            :Lin,
            Dict{Int64, Int64}(),
            Dict{Int64, Int64}(),
            Dict{Int64, Int64}(),
            Dict{Int64, Int64}(),
            :Min,
            zeros(0),
            "",
            "",
            NaN,
            zeros(0),
            :NotSolved)
    end
end

include("nl_write.jl")

MathProgBase.model(s::NLSolver) = NLMathProgModel(s.solver_command, s.options)

verify_support(c) = c

function verify_support(c::Expr)
    c
end

# function verify_support(c::Expr)
#     if c.head == :comparison
#         map(verify_support, c.args)
#         return c
#     end
#     if c.head == :call
#         if c.args[1] in [:+, :-, :*, :/, :exp, :log]
#             return c
#         elseif c.args[1] == :^
#             @assert isa(c.args[2], Real) || isa(c.args[3], Real)
#             return c
#         else
#             error("Unsupported expression $c")
#         end
#     end
#     return c
# end

function MathProgBase.loadnonlinearproblem!(m::NLMathProgModel,
    nvar, ncon, x_l, x_u, g_l, g_u, sense, d::MathProgBase.AbstractNLPEvaluator)

    @assert nvar == length(x_l) == length(x_u)
    @assert ncon == length(g_l) == length(g_u)

    m.x_l, m.x_u = x_l, x_u
    m.g_l, m.g_u = g_l, g_u
    m.sense = sense
    m.nvar, m.ncon = nvar, ncon
    m.d = d

    MathProgBase.initialize(d, [:ExprGraph])

    m.obj = verify_support(MathProgBase.obj_expr(d))
    if length(m.obj.args) < 2
        m.obj = nothing
    end
    m.vartypes = fill(:Cont, nvar)
    m.varlinearities_con = fill(:Lin, nvar)
    m.varlinearities_obj = fill(:Lin, nvar)
    m.conlinearities = fill(:Lin, ncon)

    m.j_counts = zeros(Int64, nvar)

    m.r_codes = Array(Int64, ncon)
    m.lin_constrs = Array(Dict{Int64, Float64}, ncon)

    m.constrs = map(1:ncon) do c
        verify_support(MathProgBase.constr_expr(d, c))
    end

    m.probfile = joinpath(Pkg.dir("NL"), ".solverdata", "model.nl")
    m.solfile = joinpath(Pkg.dir("NL"), ".solverdata", "model.sol")
    m
end

function MathProgBase.setvartype!(m::NLMathProgModel, cat::Vector{Symbol})
    @assert all(x-> (x in [:Cont,:Bin,:Int]), cat)
    m.vartypes = copy(cat)
end

MathProgBase.setwarmstart!(m::NLMathProgModel, v::Vector{Float64}) = m.x_0 = v

function MathProgBase.optimize!(m::NLMathProgModel)
    for (i, c) in enumerate(m.constrs)
        # Remove relations and bounds from constraint expressions
        @assert c.head == :comparison
        if length(c.args) == 3
            # Single relation constraint: expr rel bound
            m.constrs[i] = c.args[1]
            m.r_codes[i] = relation_to_nl[c.args[2]]
            if c.args[2] == [:<=, :(==)]
                m.g_u[i] = c.args[3]
            end
            if c.args[2] in [:>=, :(==)]
                m.g_l[i] = c.args[3]
            end
        else
            # Double relation constraint: bound <= expr <= bound
            m.constrs[i] = c.args[3]
            m.r_codes[i] = relation_to_nl[:multiple]
            m.g_u[i] = c.args[5]
            m.g_l[i] = c.args[1]
        end
    end

    for i in 1:m.ncon
        # Convert non-linear expression to non-linear, linear and constant
        m.lin_constrs[i] = Dict{Int64, Float64}()
        m.constrs[i], constant, m.conlinearities[i] = process_expression!(
            m.constrs[i], m.lin_constrs[i], m.varlinearities_con)

        # Update bounds on constraint
        m.g_l[i] -= constant
        m.g_u[i] -= constant

        # Update jacobian counts using the linear constraint variables
        for j in keys(m.lin_constrs[i])
            m.j_counts[j] += 1
        end
    end

    # Process objective
    if m.obj != nothing
        # Convert non-linear expression to non-linear, linear and constant
        m.obj, constant, m.objlinearity = process_expression!(
            m.obj, m.lin_obj, m.varlinearities_obj)

        # Add constant back into non-linear expression
        if constant != 0
            m.obj = add_constant(m.obj, constant)
        end
    end

    # Make sure binary vars have bounds in [0, 1]
    for i in 1:m.nvar
        if m.vartypes[i] == :Bin
            if m.x_l[i] < 0
                m.x_l[i] = 0
            end
            if m.x_u[i] > 1
                m.x_u[i] = 1
            end
        end
    end

    make_var_index!(m)
    make_con_index!(m)

    write_nl_file(m)

    options_string = join(["$name=$value" for (name, value) in m.options], " ")
    run(`$(m.solver_command) -s $(m.probfile) $options_string`)

    read_results(m)

    if m.status in [:Optimal]
        # Finally, calculate objective value for nonlinear and linear parts
        obj_nonlin = eval(substitute_vars!(deepcopy(m.obj), m.solution))
        obj_lin = evaluate_linear(m.lin_obj, m.solution)
        m.objval = obj_nonlin + obj_lin
    end
end

function process_expression!(nonlin_expr::Expr, lin_expr::Dict{Int64, Float64},
                             varlinearities::Vector{Symbol})
    # Get list of all variables in the expression
    extract_variables!(lin_expr, nonlin_expr)
    # Extract linear and constant terms from non-linear expression
    tree = LinearityExpr(nonlin_expr)
    tree = pull_up_constants(tree)
    _, tree, constant = prune_linear_terms!(tree, lin_expr)
    # Make sure all terms remaining in the tree are .nl-compatible
    nonlin_expr = convert_formula(tree)

    # Track which variables appear nonlinearly
    nonlin_vars = Dict{Int64, Float64}()
    extract_variables!(nonlin_vars, nonlin_expr)
    for j in keys(nonlin_vars)
        varlinearities[j] = :Nonlin
    end

    # Remove variables at coeff 0 that aren't also in the nonlinear tree
    for (j, coeff) in lin_expr
        if coeff == 0 && !(j in keys(nonlin_vars))
            delete!(lin_expr, j)
        end
    end

    # Mark constraint as nonlinear if anything is left in the tree
    linearity = nonlin_expr != 0 ? :Nonlin : :Lin

    return nonlin_expr, constant, linearity
end

MathProgBase.status(m::NLMathProgModel) = m.status
MathProgBase.getsolution(m::NLMathProgModel) = copy(m.solution)
MathProgBase.getobjval(m::NLMathProgModel) = m.objval

# We need to track linear coeffs of all variables present in the expression tree
extract_variables!(lin_constr::Dict{Int64, Float64}, c) = c
extract_variables!(lin_constr::Dict{Int64, Float64}, c::LinearityExpr) =
    extract_variables!(lin_constr, c.c)
function extract_variables!(lin_constr::Dict{Int64, Float64}, c::Expr)
    if c.head == :ref
        if c.args[1] == :x
            @assert isa(c.args[2], Int)
            lin_constr[c.args[2]] = 0
        else
            error("Unrecognized reference expression $c")
        end
    else
        map(arg -> extract_variables!(lin_constr, arg), c.args)
    end
end

add_constant(c, constant::Real) = c + constant
add_constant(c::Expr, constant::Real) = Expr(:call, :+, c, constant)

function make_var_index!(m::NLMathProgModel)
    nonlin_cont = Int64[]
    nonlin_int = Int64[]
    lin_cont = Int64[]
    lin_int = Int64[]
    lin_bin = Int64[]

    for i in 1:m.nvar
        if m.varlinearities_obj[i] == :Nonlin ||
           m.varlinearities_con[i] == :Nonlin
            if m.vartypes[i] == :Cont
                push!(nonlin_cont, i)
            else
                push!(nonlin_int, i)
            end
        else
            if m.vartypes[i] == :Cont
                push!(lin_cont, i)
            elseif m.vartypes[i] == :Int
                push!(lin_int, i)
            else
                push!(lin_bin, i)
            end
        end
    end

    # Index variables in required order
    for var_list in (nonlin_cont, nonlin_int, lin_cont, lin_bin, lin_int)
        add_to_index_maps!(m.v_index_map, m.v_index_map_rev, var_list)
    end
end

function make_con_index!(m::NLMathProgModel)
    nonlin_cons = Int64[]
    lin_cons = Int64[]

    for i in 1:m.ncon
        if m.conlinearities[i] == :Nonlin
            push!(nonlin_cons, i)
        else
            push!(lin_cons, i)
        end
    end
    for con_list in (nonlin_cons, lin_cons)
        add_to_index_maps!(m.c_index_map, m.c_index_map_rev, con_list)
    end
end

function add_to_index_maps!(forward_map::Dict{Int64, Int64},
                            backward_map::Dict{Int64, Int64},
                            inds::Array{Int64})
    for i in inds
        # Indices are 0-prefixed so the next index is the current dict length
        index = length(forward_map)
        forward_map[i] = index
        backward_map[index] = i
    end
end

function read_results(m::NLMathProgModel)
    f = open(m.solfile, "r")
    stat = :Undefined

    # Throw away empty first line
    line = readline(f)
    eof(f) && error()

    # Get status from second line
    line = lowercase(readline(f))
    if contains(line, "optimal")
        stat = :Optimal
    elseif contains(line, "infeasible")
        stat = :Infeasible
    elseif contains(line, "unbounded")
        stat = :Unbounded
    elseif contains(line, "error")
        stat = :Error
    end
    m.status = stat

    # Throw away lines 3-12
    for i = 3:12
        eof(f) && error()
        readline(f)
    end

    # Next, read for the variable values
    x = fill(NaN, m.nvar)
    m.objval = NaN
    if stat == :Optimal
        for index in 0:(m.nvar - 1)
            eof(f) && error("End of file while reading variables.")
            line = readline(f)

            i = m.v_index_map_rev[index]
            x[i] = float(chomp(line))
        end
        m.solution = x
    end
    nothing
end

substitute_vars!(c, x::Array{Float64}) = c
function substitute_vars!(c::Expr, x::Array{Float64})
    if c.head == :ref
        if c.args[1] == :x
            index = c.args[2]
            @assert isa(index, Int)
            c = x[index]
        else
            error("Unrecognized reference expression $c")
        end
    else
        if c.head == :call
            # Convert .nl unary minus (:neg) back to :-
            if c.args[1] == :neg
                c.args[1] = :-
            # Convert .nl :sum back to :+
            elseif c.args[1] == :sum
                c.args[1] = :+
            end
        end
        map!(arg -> substitute_vars!(arg, x), c.args)
    end
    c
end

function evaluate_linear(linear_coeffs::Dict{Int64, Float64}, x::Array{Float64})
    total = 0.0
    for (i, coeff) in linear_coeffs
        total += coeff * x[i]
    end
    total
end

end
