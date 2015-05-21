using AmplNLWriter
using FactCheck

include("nl_convert.jl")
include("nl_linearity.jl")

solvers = Any[]
push!(solvers, BonminNLSolver(["bonmin.nlp_log_level"=>0,
                               "bonmin.bb_log_level"=>0]))
push!(solvers, CouenneNLSolver(["bonmin.nlp_log_level"=>0,
                                "bonmin.bb_log_level"=>0]))

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")
for solver in solvers
    facts("[examples] test solver $(getsolvername(solver))") do
        for example in readdir(examples_path)
            include(joinpath(examples_path, example))
        end
    end
end

include(Pkg.dir("JuMP","test","runtests.jl"))

FactCheck.exitstatus()
