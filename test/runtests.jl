using AmplNLWriter, JuMP, Ipopt
using Compat
using Compat.Test

include("nl_convert.jl")
include("nl_linearity.jl")
include("nl_write.jl")
include("sol_file_parser.jl")

solvers = Any[]
push!(solvers, AmplNLSolver(Ipopt.amplexe, ["print_level=0"]))

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")

for s in solvers
    solvername = getsolvername(s)
    global solver
    solver = s
    @testset "[examples] test solver $solvername" begin
        for example in [
                "jump_nltrig.jl", "jump_nlexpr.jl", "jump_pruning.jl",
                #"jump_minlp.jl", TODO: broken (solution doesn't match)
                "jump_nonlinearbinary.jl", "jump_no_obj.jl",
                "jump_const_obj.jl",
                # "jump_maxmin.jl" TODO: broken (Unsupported operation min)
            ]
            include(joinpath(examples_path, example))
        end
    end
end

include(joinpath(dirname(pathof(JuMP)), "..", "test", "solvers.jl"))
include(joinpath(dirname(pathof(JuMP)), "..", "test", "nonlinear.jl"))
