using FactCheck

include("nl_convert.jl")

import NL
bonmin = NL.NLSolver("bonmin", print_level=0)
couenne = NL.NLSolver("couenne", tol=0.1, max_iter=2000)

nlp_solvers = Any[]
push!(nlp_solvers, bonmin)
push!(nlp_solvers, couenne)
convex_nlp_solvers = Any[]
push!(convex_nlp_solvers, bonmin)
push!(convex_nlp_solvers, couenne)
minlp_solvers = Any[]
push!(minlp_solvers, bonmin)
push!(minlp_solvers, couenne)


include(joinpath(Pkg.dir("JuMP"), "test", "nonlinear.jl"))

solver = bonmin
include(joinpath(Pkg.dir("JuMP"), "test", "hockschittkowski", "runhs.jl"))

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")
for solver in nlp_solvers
  println("With $(solver.solver_command)")
  for example in readdir(examples_path)
    include(joinpath(examples_path, example))
  end
end
