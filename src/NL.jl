module NL

using MathProgBase
importall MathProgBase.SolverInterface

import Compat

include("nl_linearity.jl")
include("nl_params.jl")
include("nl_convert.jl")

export NLSolver
immutable NLSolver <: AbstractMathProgSolver
    options
end
NLSolver(;kwargs...) = NLSolver(kwargs)

type NLMathProgModel <: AbstractMathProgModel
    options

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

    function NLMathProgModel(;options...)
        new(options,
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

MathProgBase.model(s::NLSolver) = NLMathProgModel()

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
    m.vartypes = cat
end

MathProgBase.setwarmstart!(m::NLMathProgModel, v::Vector{Float64}) = m.x_0 = v

write_nl(f, m, c) = println(f, string(c))
write_nl(f, m, c::Symbol) =  write_nl(f, m, float(eval(c)))
function write_nl(f, m, c::Real)
    if c == int(c)
        c = iround(c)
    end
    println(f, "n$c")
end
write_nl(f, m, c::LinearityExpr) = write_nl(f, m, c.c)
function write_nl(f, m, c::Expr)
    if c.head == :ref
        if c.args[1] == :x
            @assert isa(c.args[2], Int)
            println(f, string("v", m.v_index_map[c.args[2]]))
        else
            error("Unrecognized reference expression $c")
        end
    elseif c.head == :call
        println(f, string("o", func_to_nl[c.args[1]]))
        if c.args[1] in nary_functions
            println(f, (string(length(c.args) - 1)))
        end
        for arg in c.args[2:end]
            write_nl(f, m, arg)
        end
    else
        error("Unrecognized expression $c")
    end
end

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
        m.lin_constrs[i] = Dict{Int64, Float64}()
        extract_variables!(m.lin_constrs[i], m.constrs[i])

        tree = LinearityExpr(m.constrs[i])
        tree = pull_up_constants(tree)
        _, tree, constant = prune_linear_terms!(tree, m.lin_constrs[i])
        m.constrs[i]  = convert_formula(tree)
        m.g_l[i] -= constant
        m.g_u[i] -= constant

        # Get variables that are nonlinear
        nonlinear_vars = Dict{Int64, Float64}()
        extract_variables!(nonlinear_vars, m.constrs[i])
        for j in keys(nonlinear_vars)
            m.varlinearities_con[j] = :Nonlin
        end

        # Remove variables at coeff 0 that aren't also in the nonlinear tree
        for (j, coeff) in m.lin_constrs[i]
            if coeff == 0 && !(j in keys(nonlinear_vars))
                delete!(m.lin_constrs[i], j)
            end
        end

        # Mark constraint as nonlinear if anything is left in the tree
        if m.constrs[i] != 0
            m.conlinearities[i] = :Nonlin
        end

        # Update jacobian counts using the linear constraint variables
        for j in keys(m.lin_constrs[i])
            m.j_counts[j] += 1
        end
    end

    # Process objective
    if m.obj != nothing
        extract_variables!(m.lin_obj, m.obj)
        tree = LinearityExpr(m.obj)
        tree = pull_up_constants(tree)
        _, tree, constant = prune_linear_terms!(tree, m.lin_obj)
        m.obj = convert_formula(tree)

        # Get variables that are nonlinear
        nonlinear_vars = Dict{Int64, Float64}()
        extract_variables!(nonlinear_vars, m.obj)
        for j in keys(nonlinear_vars)
            m.varlinearities_obj[j] = :Nonlin
        end

        # Remove variables at coeff 0 that aren't also in the nonlinear tree
        for (j, coeff) in m.lin_obj
            if coeff == 0 && !(j in keys(nonlinear_vars))
                delete!(m.lin_obj, j)
            end
        end

        # Mark constraint as nonlinear if anything is left in the tree
        if m.obj != 0
            m.objlinearity = :Nonlin
        end

        # Add constant back into tree
        m.obj = add_constant(m.obj, constant)
    end

    make_var_index(m)
    make_con_index(m)

    write_nl_file(m)
    run(`couenne $(m.probfile)`)
    read_results(m)
end

MathProgBase.status(m::NLMathProgModel) = m.status
MathProgBase.getsolution(m::NLMathProgModel) = m.solution
MathProgBase.getobjval(m::NLMathProgModel) = m.objval

# We need to track linear coeffs of all variables present in the expression tree
extract_variables!(lin_constr::Dict{Int64, Float64}, c) = c
extract_variables!(lin_constr::Dict{Int64, Float64}, c::LinearityExpr) =
    extract_variables!(lin_constr, c.c)
function extract_variables!(lin_constr::Dict{Int64, Float64}, c::Expr)
    if c.head == :call
        for i = 2:length(c.args)
            extract_variables!(lin_constr, c.args[i])
        end
    elseif c.head == :ref
        if c.args[1] == :x
            @assert isa(c.args[2], Int)
            lin_constr[c.args[2]] = 0
        else
            error("Unrecognized reference expression $c")
        end
    end
end

add_constant(c, constant::Real) = c + constant
add_constant(c::Expr, constant::Real) = Expr(:call, :+, c, constant)

function make_var_index(m::NLMathProgModel)
    nonlinear_cont = Int64[]
    nonlinear_int = Int64[]
    linear_cont = Int64[]
    linear_int = Int64[]
    linear_bin = Int64[]

    for i in 1:m.nvar
        if m.varlinearities_obj[i] == :Nonlin ||
           m.varlinearities_con[i] == :Nonlin
            if m.vartypes[i] == :Cont
                push!(nonlinear_cont, i)
            else
                push!(nonlinear_int, i)
            end
        else
            if m.vartypes[i] == :Cont
                push!(linear_cont, i)
            elseif m.vartypes[i] == :Int
                push!(linear_int, i)
            else
                push!(linear_bin, i)
            end
        end
    end

    index = 0
    # 1st: Nonlinear cont
    index = add_to_var_index(m, nonlinear_cont, index)
    # 2nd: Nonlinear int
    index = add_to_var_index(m, nonlinear_int, index)
    # 3rd: Linear cont
    index = add_to_var_index(m, linear_cont, index)
    # 4th: Linear bin
    index = add_to_var_index(m, linear_bin, index)
    # 5th: Linear int
    index = add_to_var_index(m, linear_int, index)
end

function add_to_var_index(m::NLMathProgModel, inds::Array{Int64}, index::Int64)
    for i in inds
        m.v_index_map[i] = index
        m.v_index_map_rev[index] = i
        index += 1
    end
    return index
end

function make_con_index(m::NLMathProgModel)
    nonlinear_cons = Int64[]
    linear_cons = Int64[]

    for i in 1:m.ncon
        if m.conlinearities[i] == :Nonlin
            push!(nonlinear_cons, i)
        else
            push!(linear_cons, i)
        end
    end
    index = 0
    # 1st: Nonlinear
    index = add_to_con_index(m, nonlinear_cons, index)
    # 2nd: Linear
    index = add_to_con_index(m, linear_cons, index)
end

function add_to_con_index(m::NLMathProgModel, inds::Array{Int64}, index::Int64)
    for i in inds
        m.c_index_map[i] = index
        m.c_index_map_rev[index] = i
        index += 1
    end
    return index
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

end
