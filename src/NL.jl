module NL

using MathProgBase
importall MathProgBase.SolverInterface

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
    println(c)
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

function MathProgBase.optimize!(m::NLMathProgModel)
    println("Not yet!")
end

MathProgBase.status(m::NLMathProgModel) = m.status
MathProgBase.getsolution(m::NLMathProgModel) = m.solution
MathProgBase.getobjval(m::NLMathProgModel) = m.objval

end
