# Copyright (c) 2015: AmplNLWriter.jl contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using Test

import AmplNLWriter
import Bonmin_jll
import Couenne_jll
import Ipopt_jll
import MathOptInterface as MOI
import MINLPTests
import SHOT_jll
import Uno_jll

const TERMINATION_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => MOI.LOCALLY_SOLVED,
    MINLPTests.INFEASIBLE_PROBLEM => MOI.LOCALLY_INFEASIBLE,
)

const PRIMAL_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => MOI.FEASIBLE_POINT,
    MINLPTests.INFEASIBLE_PROBLEM => MOI.NO_SOLUTION,
)

# Common reasons for exclusion:
# nlp/006_010     : Uses a user-defined function
# nlp/007_010     : Ipopt returns an infeasible point, not NO_SOLUTION.
# nlp/008_010     : Couenne fails to converge
# nlp/008_011     : Couenne fails to converge
# nlp/009_010     : min not implemented
# nlp/009_011     : max not implemented
# nlp-cvx/109_010 : Ipopt fails to converge
# nlp-cvx/206_010 : Couenne can't evaluate pow
# nlp-mi/001_010  : Couenne fails to converge

const CONFIG = Dict{String,Any}(
    "Bonmin" => Dict(
        "mixed-integer" => true,
        "amplexe" => Bonmin_jll.amplexe,
        "options" => String["bonmin.nlp_log_level=0"],
        "dual_tol" => NaN,
        "nlpcvx_exclude" => ["109_010"],
        # 004_010 and 004_011 are tolerance failures on Bonmin
        "nlpmi_exclude" => ["004_010", "004_011"],
    ),
    "Couenne" => Dict(
        "mixed-integer" => true,
        "amplexe" => Couenne_jll.amplexe,
        "options" => String[],
        "tol" => 1e-2,
        "dual_tol" => NaN,
        "nlp_exclude" => ["008_010", "008_011", "009_010", "009_011"],
        "nlpcvx_exclude" => ["109_010", "206_010"],
        "nlpmi_exclude" => ["001_010"],
    ),
    "Ipopt" => Dict(
        "mixed-integer" => false,
        "amplexe" => Ipopt_jll.amplexe,
        "options" => String["print_level=0"],
        "nlp_exclude" => ["007_010"],
        "nlpcvx_exclude" => ["109_010"],
    ),
    # SHOT fails too many tests to recommend using it.
    # e.g., https://github.com/coin-or/SHOT/issues/134
    # Even problems such as `@variable(model, x); @objective(model, Min, (x-1)^2)`
    # "SHOT" => Dict(
    #     "amplexe" => SHOT_jll.amplexe,
    #     "options" => String[
    #         "Output.Console.LogLevel=6",
    #         "Output.File.LogLevel=6",
    #         "Termination.ObjectiveGap.Absolute=1e-6",
    #         "Termination.ObjectiveGap.Relative=1e-6",
    #     ],
    #     "tol" => 1e-2,
    #     "dual_tol" => NaN,
    #     "infeasible_point" => AmplNLWriter.MOI.UNKNOWN_RESULT_STATUS,
    # ),
    "Uno" => Dict(
        "mixed-integer" => false,
        "amplexe" => Uno_jll.amplexe,
        "options" => ["logger=SILENT"],
        "nlp_exclude" => [
            # See https://github.com/cvanaret/Uno/issues/39
            "005_010",
            # See https://github.com/cvanaret/Uno/issues/38
            "007_010",
        ],
    ),
)

@testset "$k" for (k, config) in CONFIG
    OPTIMIZER =
        () -> AmplNLWriter.Optimizer(config["amplexe"], config["options"])
    # PRIMAL_TARGET[MINLPTests.INFEASIBLE_PROBLEM] = config["infeasible_point"]
    @testset "NLP" begin
        exclude = vcat(get(config, "nlp_exclude", String[]), ["006_010"])
        MINLPTests.test_nlp(
            OPTIMIZER;
            exclude = exclude,
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
        MINLPTests.test_nlp_expr(
            OPTIMIZER;
            exclude = exclude,
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
    end
    @testset "NLP-CVX" begin
        exclude = get(config, "nlpcvx_exclude", String[])
        MINLPTests.test_nlp_cvx(
            OPTIMIZER;
            exclude = exclude,
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
        MINLPTests.test_nlp_cvx_expr(
            OPTIMIZER;
            exclude = exclude,
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
    end
    if config["mixed-integer"]
        exclude = vcat(get(config, "nlpmi_exclude", String[]), ["006_010"])
        @testset "NLP-MI" begin
            MINLPTests.test_nlp_mi(
                OPTIMIZER;
                exclude = exclude,
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = get(config, "tol", 1e-5),
                primal_tol = get(config, "tol", 1e-5),
                dual_tol = get(config, "dual_tol", 1e-5),
            )
            MINLPTests.test_nlp_mi_expr(
                OPTIMIZER;
                exclude = exclude,
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = get(config, "tol", 1e-5),
                primal_tol = get(config, "tol", 1e-5),
                dual_tol = get(config, "dual_tol", 1e-5),
            )
        end
    end
end
