using AmplNLWriter, JuMP, Ipopt
using Base.Test

include("nl_convert.jl")
include("nl_linearity.jl")
include("nl_write.jl")
include("sol_file_parser.jl")

# needed for the scoping of `solver` in the examples
solver = JuMP.UnsetSolver()
solvers = Any[]
push!(solvers, AmplNLSolver(Ipopt.amplexe, ["print_level=0"]))

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")

for solver in solvers
    solvername = getsolvername(solver)
    @testset "[examples] test solver $solvername" begin
        for example in [
                "jump_nltrig.jl", "jump_nlexpr.jl", "jump_pruning.jl",
                "jump_minlp.jl", "jump_nonlinearbinary.jl", "jump_no_obj.jl",
                "jump_const_obj.jl", "jump_maxmin.jl"
            ]
            include(joinpath(examples_path, example))
        end
    end
end

include(Pkg.dir("JuMP","test","solvers.jl"))
include(Pkg.dir("JuMP","test","nonlinear.jl"))
