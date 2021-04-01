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
            "007_010",  # Infeasible model
        ],
        "nlp_cvx" => String[
            "109_010"  # Ipopt fails to converge
        ],
        "nlp_mi" => String[

        ],
    ),
    "Ipopt" => Dict(
        "nlp" => String[
            "005_011",  # Uses the function `\`
            "006_010",  # User-defined function
            "007_010",  # Infeasible model
        ],
        "nlp_cvx" => String[
            "109_010"  # Ipopt fails to converge
        ],
    ),
)

@testset "$(name)" for (name, amplexe) in FUNCTIONS
    amplexe() do path
        OPTIMIZER = () -> AmplNLWriter.Optimizer(path, ["print_level=0"])
        MINLPTests.test_nlp(
            OPTIMIZER,
            exclude = EXCLUDES[name]["nlp"],
            objective_tol = 1e-5,
            primal_tol = 1e-5,
            dual_tol = NaN,
        )
        @testset "nlp_007_010" begin
            MINLPTests.nlp_007_010(
                OPTIMIZER,
                1e-5,
                NaN,
                NaN,
                Dict(MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.INFEASIBLE),
                Dict(MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.NO_SOLUTION),
            )
        end
        MINLPTests.test_nlp_cvx(OPTIMIZER, EXCLUDES[name]["nlp_cvx"])
        if name == "Bonmin"
            MINLPTests.test_nlp_mi(OPTIMIZER, EXCLUDES[name]["nlp_mi"])
        end
    end
end
