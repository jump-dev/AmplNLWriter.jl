using AmplNLWriter, Compat, FactCheck, JuMP
using Base.Test

include("nl_convert.jl")
include("nl_linearity.jl")
include("nl_write.jl")

solver = JuMP.UnsetSolver()
solvers = Any[]
push!(solvers, IpoptNLSolver(["print_level=0"]))
push!(solvers, BonminNLSolver(["bonmin.nlp_log_level=0";
                               "bonmin.bb_log_level=0"]))
push!(solvers, CouenneNLSolver(["bonmin.nlp_log_level=0";
                                "bonmin.bb_log_level=0"]))
# Add tolerance option for couenne
open("couenne.opt", "w") do f
  write(f, "allowable_fraction_gap 0.0001")
end

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")
for solver in solvers
    solvername = getsolvername(solver)
    facts("[examples] test solver $solvername") do
        for example in ["jump_nltrig.jl"]
            include(joinpath(examples_path, example))
        end
        if solvername != "ipopt"
            for example in ["jump_pruning.jl", "jump_minlp.jl",
                            "jump_nonlinearbinary.jl"]
                include(joinpath(examples_path, example))
            end
        end
        if solvername == "ipopt"
            for example in ["jump_maxmin.jl"]
                include(joinpath(examples_path, example))
            end
        end
    end
end

include(Pkg.dir("JuMP","test","solvers.jl"))
include(Pkg.dir("JuMP","test","nonlinear.jl"))

rm("couenne.opt")

FactCheck.exitstatus()
