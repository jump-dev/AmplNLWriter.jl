if VERSION < v"1.3"
    error("You must use Julia 1.3 or newer.")
end

import AmplNLWriter
import Bonmin_jll
import Couenne_jll
import Ipopt_jll
import MINLPTest
using Test

const TERMINATION_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_SOLVED,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.INFEASIBLE,
)

const PRIMAL_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.FEASIBLE_POINT,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.UNKNOWN_RESULT_STATUS,
)

const CONFIG = Dict(
    "Bonmin" => Dict(
        "amplexe" => Bonmin_jll.amplexe,
        "options" => ["bonmin.print_level=0"],
        "tol" => 1e-5,
        "nlp_exclude" => ["005_011", "006_010"],
        "nlpcvx_exclude" => ["109_010"],
        "nlpmi_exclude" => ["005_011", "006_010"],
    ),
    "Couenne" => Dict(
        "amplexe" => Couenne_jll.amplexe,
        "options" => [],
        "tol" => 1e-2,
        "nlp_exclude" => ["005_011", "006_010", "008_010", "008_011"],
        "nlpcvx_exclude" => ["109_010", "206_010"],
        "nlpmi_exclude" => ["001_010", "005_011", "006_010"],
    ),
    "Ipopt" => Dict(
        "amplexe" => Ipopt_jll.amplexe,
        "options" => ["print_level=0"],
        "tol" => 1e-5,
        "nlp_exclude" => ["005_011", "006_010"],
        "nlpcvx_exclude" => ["109_010"],
        "nlpmi_exclude" => ["005_011", "006_010"],
    )
)

@testset "$(name)" for (name, config) in CONFIG
    OPTIMIZER =
        () -> AmplNLWriter.Optimizer(config["amplexe"], config["options"])
    @testset "NLP" begin
        MINLPTests.test_nlp(
            OPTIMIZER,
            exclude = config["nlp_exlude"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = config["tol"],
            primal_tol = config["tol"],
            dual_tol = NaN,
        )
    end
    @testset "NLP-CVX" begin
        MINLPTests.test_nlp_cvx(
            OPTIMIZER,
            exclude = config["nlpcvx_exlude"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = config["tol"],
            primal_tol = config["tol"],
            dual_tol = NaN,
        )
    end
    if name != "Ipopt"
        @testset "NLP-MI" begin
            MINLPTests.test_nlp_mi(
                OPTIMIZER,
                exclude = config["nlpmi_exclude"],
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = config["tol"],
                primal_tol = config["tol"],
                dual_tol = NaN,
            )
        end
    end
end
