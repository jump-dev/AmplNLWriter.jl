using FactCheck

include("nl_convert.jl")

import NL
solver = NL.NLSolver()

nlp_solvers = Any[]
push!(nlp_solvers, solver)
convex_nlp_solvers = Any[]
push!(convex_nlp_solvers, solver)
minlp_solvers = Any[]
push!(minlp_solvers, solver)


include(joinpath(Pkg.dir("JuMP"), "test", "nonlinear.jl"))

include(joinpath(Pkg.dir("JuMP"), "test", "hockschittkowski", "runhs.jl"))

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")
for example in readdir(examples_path)
  include(joinpath(examples_path, example))
end
