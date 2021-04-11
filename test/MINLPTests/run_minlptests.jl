import AmplNLWriter
import MINLPTests
using Test

const FUNCTIONS = if VERSION < v"1.3"
    import Ipopt
    [("Ipopt", Ipopt.amplexe)]
else
    import Bonmin_jll, Couenne_jll, Ipopt_jll
    [
        ("Bonmin", Bonmin_jll.amplexe),
        ("Couenne", Couenne_jll.amplexe),
        ("Ipopt", Ipopt_jll.amplexe),
    ]
end

const TERMINATION_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_SOLVED,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.INFEASIBLE,
)

const PRIMAL_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.FEASIBLE_POINT,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.NO_SOLUTION,
)

# @testset "$(name)" 
for (name, amplexe) in FUNCTIONS
    OPTIMIZER = () -> AmplNLWriter.Optimizer(amplexe, ["print_level=0"])
    @testset "NLP" begin
        MINLPTests.test_nlp(
            OPTIMIZER,
            exclude = String[
                "005_011",  # Uses the function `\`
                "006_010",  # User-defined function
            ],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            # objective_tol = 1e-5,
            # primal_tol = 1e-5,
            # dual_tol = NaN,
        )
    end
    @testset "NLP-CVX" begin
        MINLPTests.test_nlp_cvx(
            OPTIMIZER,
            exclude = String[
                "109_010",  # Ipopt fails to converge
            ],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
        )
    end
    if name != "Ipopt"
        @testset "NLP-MI" begin
            MINLPTests.test_nlp_mi(
                OPTIMIZER,
                exclude = String[
                    "005_011",  # Uses the function `\`
                    "006_010",  # User-defined function
                ],
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
            )
        end
    end
end
