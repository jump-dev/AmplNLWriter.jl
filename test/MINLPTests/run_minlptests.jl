import AmplNLWriter
import MINLPTests
using Test

const FUNCTIONS = Dict()

if VERSION < v"1.3"
    import Ipopt
    FUNCTIONS["Ipopt"] = f -> f(Ipopt.amplexe)
else
    import Ipopt_jll
    import Bonmin_jll
    FUNCTIONS["Ipopt"] = f -> Ipopt_jll.amplexe(f)
    FUNCTIONS["Bonmin"] = f -> Bonmin_jll.amplexe(f)
end

const EXCLUDES = Dict(
    "Bonmin" => Dict(
        "nlp" => String[
            "005_011",  # Uses the function `\`
            "006_010",  # User-defined function
        ],
        "nlp_cvx" => String[
            "109_010"  # Ipopt fails to converge
        ],
        "nlp_mi" => String[
            "005_011",  # Uses the function `\`
            "006_010",  # User-defined function
        ],
    ),
    "Ipopt" => Dict(
        "nlp" => String[
            "005_011",  # Uses the function `\`
            "006_010",  # User-defined function
        ],
        "nlp_cvx" => String[
            "109_010"  # Ipopt fails to converge
        ],
    ),
)

const TERMINATION_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_SOLVED,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.INFEASIBLE,
)

const PRIMAL_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.FEASIBLE_POINT,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.NO_SOLUTION,
)

@testset "$(name)" for (name, amplexe) in FUNCTIONS
    amplexe() do path
        OPTIMIZER = () -> AmplNLWriter.Optimizer(path, ["print_level=0"])
        MINLPTests.test_nlp(
            OPTIMIZER,
            exclude = EXCLUDES[name]["nlp"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = 1e-5,
            primal_tol = 1e-5,
            dual_tol = NaN,
        )
        MINLPTests.test_nlp_cvx(OPTIMIZER, exclude = EXCLUDES[name]["nlp_cvx"])
        if name == "Bonmin"
            MINLPTests.test_nlp_mi(
                OPTIMIZER, 
                exclude = EXCLUDES[name]["nlp_mi"],
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
            )
        end
    end
end
