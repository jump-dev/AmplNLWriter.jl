# Copyright (c) 2015: AmplNLWriter.jl contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import AmplNLWriter
import MINLPTests
using Test

const TERMINATION_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_SOLVED,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_INFEASIBLE,
)

const PRIMAL_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.FEASIBLE_POINT,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.NO_SOLUTION,
)

# Common reasons for exclusion:
# nlp/005_011     : Uses the function `\`
# nlp/006_010     : Uses a user-defined function
# nlp/007_010     : Ipopt returns an infeasible point, not NO_SOLUTION.
# nlp/008_010     : Couenne fails to converge
# nlp/008_011     : Couenne fails to converge
# nlp/009_010     : min not implemented
# nlp/009_011     : max not implemented
# nlp-cvx/109_010 : Ipopt fails to converge
# nlp-cvx/206_010 : Couenne can't evaluate pow
# nlp-mi/001_010  : Couenne fails to converge

const CONFIG = Dict{String,Any}()

import Bonmin_jll
CONFIG["Bonmin"] = Dict(
    "mixed-integer" => true,
    "amplexe" => Bonmin_jll.amplexe,
    "options" => String["bonmin.nlp_log_level=0"],
    "tol" => 1e-5,
    "dual_tol" => NaN,
    "nlp_exclude" => ["005_011", "006_010"],
    "nlpcvx_exclude" => ["109_010"],
    # 004_010 and 004_011 are tolerance failures on Bonmin
    "nlpmi_exclude" => ["004_010", "004_011", "005_011", "006_010"],
    "infeasible_point" => AmplNLWriter.MOI.NO_SOLUTION,
)

import Couenne_jll
CONFIG["Couenne"] = Dict(
    "mixed-integer" => true,
    "amplexe" => Couenne_jll.amplexe,
    "options" => String[],
    "tol" => 1e-2,
    "dual_tol" => NaN,
    "nlp_exclude" =>
        ["005_011", "006_010", "008_010", "008_011", "009_010", "009_011"],
    "nlpcvx_exclude" => ["109_010", "206_010"],
    "nlpmi_exclude" => ["001_010", "005_011", "006_010"],
    "infeasible_point" => AmplNLWriter.MOI.NO_SOLUTION,
)

import Ipopt_jll
CONFIG["Ipopt"] = Dict(
    "mixed-integer" => false,
    "amplexe" => Ipopt_jll.amplexe,
    "options" => String["print_level=0"],
    "tol" => 1e-5,
    "dual_tol" => 1e-5,
    "nlp_exclude" => ["005_011", "006_010", "007_010"],
    "nlpcvx_exclude" => ["109_010"],
    "nlpmi_exclude" => ["005_011", "006_010"],
    "infeasible_point" => AmplNLWriter.MOI.NO_SOLUTION,
)

# SHOT fails too many tests to recommend using it.
# e.g., https://github.com/coin-or/SHOT/issues/134
# Even problems such as `@variable(model, x); @objective(model, Min, (x-1)^2)`
#
# import SHOT_jll
# CONFIG["SHOT"] = Dict(
#     "amplexe" => SHOT_jll.amplexe,
#     "options" => String[
#         "Output.Console.LogLevel=6",
#         "Output.File.LogLevel=6",
#         "Termination.ObjectiveGap.Absolute=1e-6",
#         "Termination.ObjectiveGap.Relative=1e-6",
#     ],
#     "tol" => 1e-2,
#     "dual_tol" => NaN,
#     "nlp_exclude" => [
#         "005_011",  # `\` function
#         "006_010",  # User-defined function
#     ],
#     "nlpcvx_exclude" => [
#         "501_011",  # `\` function
#     ],
#     "nlpmi_exclude" => [
#         "005_011",  # `\` function
#         "006_010",  # User-defined function
#     ],
#     "infeasible_point" => AmplNLWriter.MOI.UNKNOWN_RESULT_STATUS,
# )

import Uno_jll

CONFIG["Uno"] = Dict(
    "mixed-integer" => false,
    "amplexe" => Uno_jll.amplexe,
    "options" => ["logger=SILENT"],
    "tol" => 1e-5,
    "dual_tol" => 1e-5,
    "nlp_exclude" => String[],
    #    ["005_010", "006_010", "007_010", "008_010", "008_011"],
    "nlpcvx_exclude" => String[],
    "nlpmi_exclude" => String[],
    "infeasible_point" => AmplNLWriter.MOI.NO_SOLUTION,
)

@testset "$(name)" for name in ["Uno", "Ipopt", "Bonmin", "Couenne"]
    config = CONFIG[name]
    OPTIMIZER =
        () -> AmplNLWriter.Optimizer(config["amplexe"], config["options"])
    PRIMAL_TARGET[MINLPTests.INFEASIBLE_PROBLEM] = config["infeasible_point"]
    @testset "NLP" begin
        MINLPTests.test_nlp(
            OPTIMIZER,
            exclude = config["nlp_exclude"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = config["tol"],
            primal_tol = config["tol"],
            dual_tol = config["dual_tol"],
        )
        MINLPTests.test_nlp_expr(
            OPTIMIZER,
            exclude = config["nlp_exclude"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = config["tol"],
            primal_tol = config["tol"],
            dual_tol = config["dual_tol"],
        )
    end
    @testset "NLP-CVX" begin
        MINLPTests.test_nlp_cvx(
            OPTIMIZER,
            exclude = config["nlpcvx_exclude"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = config["tol"],
            primal_tol = config["tol"],
            dual_tol = config["dual_tol"],
        )
        MINLPTests.test_nlp_cvx_expr(
            OPTIMIZER,
            exclude = config["nlpcvx_exclude"],
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = config["tol"],
            primal_tol = config["tol"],
            dual_tol = config["dual_tol"],
        )
    end
    if config["mixed-integer"]
        @testset "NLP-MI" begin
            MINLPTests.test_nlp_mi(
                OPTIMIZER,
                exclude = config["nlpmi_exclude"],
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = config["tol"],
                primal_tol = config["tol"],
                dual_tol = config["dual_tol"],
            )
            MINLPTests.test_nlp_mi_expr(
                OPTIMIZER,
                exclude = config["nlpmi_exclude"],
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = config["tol"],
                primal_tol = config["tol"],
                dual_tol = config["dual_tol"],
            )
        end
    end
end
