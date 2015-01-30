module NL

using MathProgBase
importall MathProgBase.SolverInterface

import Compat

include("nl_params.jl")

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
    constrs

    vartypes::Vector{Symbol}

    v_names::Vector{String}
    c_names::Vector{String}

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
            Expr[],
            Symbol[],
            String[],
            String[],
            :Min,
            zeros(0),
            "",
            "",
            NaN,
            zeros(0),
            :NotSolved)
    end
end

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
    m.vartypes = fill(:Cont, nvar)

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

add_indent(c::String, indent::Int) = println(string(repeat(" ", indent), c))

to_nl(m, c, indent::Int=0) = add_indent(string(c), indent)
to_nl(m, c::Real, indent::Int=0) = add_indent("n$c", indent)
function to_nl(m, c::Expr, indent::Int=0)
    if c.head == :ref
        if c.args[1] == :x
            @assert isa(c.args[2], Int)
            add_indent("v$(m.v_names[c.args[2]])", indent)
        else
            error("Unrecognized reference expression $c")
        end
    elseif c.head == :call
        add_indent("o$(func_to_nl[c.args[1]])", indent)
        for arg in c.args[2:end]
            to_nl(m, arg, indent + 2)
        end
    else
        println(string(repeat(" ", indent), c.head, " ", length(c.args)))
        for arg in c.args
            to_nl(m, arg, indent + 2)
        end
    end
end

function MathProgBase.optimize!(m::NLMathProgModel)

    m.v_names = ["$i" for i in 1:m.nvar]
    m.c_names = ["$i" for i in 1:m.ncon]

    m.constrs = map(1:m.ncon) do c
        to_nl(m, MathProgBase.constr_expr(m.d, c))
    end
end

MathProgBase.status(m::NLMathProgModel) = m.status
MathProgBase.getsolution(m::NLMathProgModel) = m.solution
MathProgBase.getobjval(m::NLMathProgModel) = m.objval

end
