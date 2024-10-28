# Copyright (c) 2015: AmplNLWriter.jl contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using Test

import AmplNLWriter
import Bonmin_jll
import Couenne_jll
import Ipopt_jll
import MINLPTests
import SHOT_jll
import Uno_jll

const TERMINATION_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_SOLVED,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.LOCALLY_INFEASIBLE,
)

const PRIMAL_TARGET = Dict(
    MINLPTests.FEASIBLE_PROBLEM => AmplNLWriter.MOI.FEASIBLE_POINT,
    MINLPTests.INFEASIBLE_PROBLEM => AmplNLWriter.MOI.NO_SOLUTION,
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
        "nlpmi_exclude" => ["004_010", "004_011", "006_010"],
    ),
    "Couenne" => Dict(
        "mixed-integer" => true,
        "amplexe" => Couenne_jll.amplexe,
        "options" => String[],
        "tol" => 1e-2,
        "dual_tol" => NaN,
        "nlp_exclude" =>
            ["006_010", "008_010", "008_011", "009_010", "009_011"],
        "nlpcvx_exclude" => ["109_010", "206_010"],
        "nlpmi_exclude" => ["001_010", "006_010"],
    ),
    "Ipopt" => Dict(
        "mixed-integer" => false,
        "amplexe" => Ipopt_jll.amplexe,
        "options" => String["print_level=0"],
        "nlp_exclude" => ["006_010", "007_010"],
        "nlpcvx_exclude" => ["109_010"],
        "nlpmi_exclude" => ["006_010"],
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
            # Unsupported user-defined function
            "006_010",
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
        MINLPTests.test_nlp(
            OPTIMIZER,
            exclude = get(config, "nlp_exclude", ["006_010"]),
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
        MINLPTests.test_nlp_expr(
            OPTIMIZER,
            exclude = get(config, "nlp_exclude", ["006_010"]),
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
    end
    @testset "NLP-CVX" begin
        MINLPTests.test_nlp_cvx(
            OPTIMIZER,
            exclude = get(config, "nlpcvx_exclude", String[]),
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
        MINLPTests.test_nlp_cvx_expr(
            OPTIMIZER,
            exclude = get(config, "nlpcvx_exclude", String[]),
            termination_target = TERMINATION_TARGET,
            primal_target = PRIMAL_TARGET,
            objective_tol = get(config, "tol", 1e-5),
            primal_tol = get(config, "tol", 1e-5),
            dual_tol = get(config, "dual_tol", 1e-5),
        )
    end
    if config["mixed-integer"]
        @testset "NLP-MI" begin
            MINLPTests.test_nlp_mi(
                OPTIMIZER,
                exclude = get(config, "nlpmi_exclude", ["006_010"]),
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = get(config, "tol", 1e-5),
                primal_tol = get(config, "tol", 1e-5),
                dual_tol = get(config, "dual_tol", 1e-5),
            )
            MINLPTests.test_nlp_mi_expr(
                OPTIMIZER,
                exclude = get(config, "nlpmi_exclude", ["006_010"]),
                termination_target = TERMINATION_TARGET,
                primal_target = PRIMAL_TARGET,
                objective_tol = get(config, "tol", 1e-5),
                primal_tol = get(config, "tol", 1e-5),
                dual_tol = get(config, "dual_tol", 1e-5),
            )
        end
    end
end

function test_uno_runtests()
    optimizer = MOI.instantiate(
        () -> AmplNLWriter.Optimizer(Uno_jll.amplexe, ["logger=SILENT"]);
        with_cache_type = Float64,
        with_bridge_type = Float64,
    )
    MOI.Test.runtests(
        optimizer,
        MOI.Test.Config(
            atol = 1e-4,
            rtol = 1e-4,
            optimal_status = MOI.LOCALLY_SOLVED,
            infeasible_status = MOI.LOCALLY_INFEASIBLE,
            exclude = Any[
                MOI.VariableBasisStatus,
                MOI.ConstraintBasisStatus,
                MOI.ObjectiveBound,
            ],
        );
        exclude = [
            # OTHER_LIMIT instead of LOCALLY_SOLVED
            r"^test_conic_linear_VectorOfVariables_2$",
            r"^test_nonlinear_expression_hs109$",
            r"^test_quadratic_constraint_GreaterThan$",
            r"^test_quadratic_constraint_LessThan$",
            r"^test_solve_VariableIndex_ConstraintDual_MAX_SENSE$",
            r"^test_solve_VariableIndex_ConstraintDual_MIN_SENSE$",
            # OTHER_ERROR instead of LOCALLY_SOLVED
            r"^test_linear_integration$",
            r"^test_linear_transform$",
            # OTHER_LIMIT instead of DUAL_INFEASIBLE
            r"^test_solve_TerminationStatus_DUAL_INFEASIBLE$",
            # OTHER_LIMIT instead of LOCALLY_INFEASIBLE
            r"^test_conic_NormInfinityCone_INFEASIBLE$",
            r"^test_conic_NormOneCone_INFEASIBLE$",
            r"^test_conic_linear_INFEASIBLE$",
            r"^test_conic_linear_INFEASIBLE_2$",
            r"^test_linear_INFEASIBLE$",
            r"^test_linear_INFEASIBLE_2$",
            r"^test_solve_DualStatus_INFEASIBILITY_CERTIFICATE_",
            # Uno does not support integrality
            "Indicator",
            r"[Ii]nteger",
            "Semicontinuous",
            "Semiinteger",
            "SOS1",
            "SOS2",
            "ZeroOne",
            r"^test_cpsat_",
            # Existing MOI issues
            r"^test_attribute_SolverVersion$",
            r"^test_nonlinear_invalid$",
            r"^test_basic_VectorNonlinearFunction_",
        ],
    )
    return
end

test_uno_runtests()
