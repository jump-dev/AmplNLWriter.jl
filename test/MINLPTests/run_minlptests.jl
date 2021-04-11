import AmplNLWriter
import MINLPTests
using Test

if VERSION < v"1.3"
    import Ipopt
    run_with_ampl(f) = f(Ipopt.amplexe)
else
    import Ipopt_jll
    run_with_ampl(f) = Ipopt_jll.amplexe(f)
end

const MOI = AmplNLWriter.MOI

run_with_ampl() do path
    OPTIMIZER =
        () -> MOI.Utilities.CachingOptimizer(
            MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
            AmplNLWriter.Optimizer(path, ["print_level=0"]),
        )
    ###
    ### src/nlp tests.
    ###

    MINLPTests.test_nlp(
        OPTIMIZER,
        exclude = [
            "005_011",  # Uses the function `\`
            "006_010",  # User-defined function
            "007_010",  # Infeasible model
        ],
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
            Dict(
                MINLPTests.INFEASIBLE_PROBLEM =>
                    AmplNLWriter.MOI.UNKNOWN_RESULT_STATUS,
            ),
        )
    end

    ###
    ### src/nlp-cvx tests.
    ###

    return MINLPTests.test_nlp_cvx(OPTIMIZER, exclude = [
        "109_010",  # Ipopt fails to converge
    ])
end
