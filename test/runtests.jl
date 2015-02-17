using FactCheck

include("nl_convert.jl")

import NL

nlp_solvers = Any[]
push!(nlp_solvers, NL.NLSolver())
convex_nlp_solvers = Any[]
push!(convex_nlp_solvers, NL.NLSolver())

include(joinpath(Pkg.dir("JuMP"), "test", "nonlinear.jl"))
