# Copyright (c) 2015: AmplNLWriter.jl contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module TestMOIWrapper

using Test

import AmplNLWriter
import AmplNLWriter: MOI
import Ipopt_jll
import Uno_jll

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
    return
end

function ipopt_optimizer(path = Ipopt_jll.amplexe; kwargs...)
    model = AmplNLWriter.Optimizer(path; kwargs...)
    MOI.set(model, MOI.RawOptimizerAttribute("print_level"), 0)
    MOI.set(model, MOI.RawOptimizerAttribute("sb"), "yes")
    MOI.set(
        model,
        MOI.RawOptimizerAttribute("option_file_name"),
        joinpath(@__DIR__, "ipopt.opt"),
    )
    return MOI.Utilities.CachingOptimizer(
        MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
        MOI.Bridges.full_bridge_optimizer(
            MOI.Utilities.CachingOptimizer(
                MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
                model,
            ),
            Float64,
        ),
    )
end

function test_ipopt_runtests()
    MOI.Test.runtests(
        ipopt_optimizer(),
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
        ),
        exclude = [
            # TODO(odow): Bug in MOI/AmplNLWriter
            "test_model_copy_to_",
            # TODO(odow): implement
            "test_attribute_SolverVersion",
            # Skip the test with NaNs
            "test_nonlinear_invalid",
            # Returns UnknownResultStatus
            "test_conic_NormInfinityCone_INFEASIBLE",
            "test_conic_NormOneCone_INFEASIBLE",
            "test_conic_linear_VectorOfVariables_2",
            # Ipopt doesn't support integrality
            "_ObjectiveBound_",
            "_ZeroOne_",
            "_Semicontinuous_",
            "_Semiinteger_",
            "_Integer_",
            "_Indicator_",
            "_SOS2_",
            "test_linear_integer_",
            "test_cpsat_",
        ],
    )
    return
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
                # Bug: Uno returns incorrect duals, and does not support
                # variable duals.
                MOI.ConstraintDual,
            ],
        ),
        exclude = [
            # OTHER_LIMIT instead of LOCALLY_SOLVED
            "test_conic_linear_VectorOfVariables_2",
            "test_nonlinear_expression_hs109",
            "test_quadratic_constraint_GreaterThan",
            "test_quadratic_constraint_LessThan",
            # OTHER_ERROR instead of LOCALLY_SOLVED
            "test_linear_integer_integration",
            "test_linear_integration",
            "test_linear_transform",
            # OTHER_LIMIT instead of DUAL_INFEASIBLE
            "test_solve_TerminationStatus_DUAL_INFEASIBLE",
            # OTHER_LIMIT instead of LOCALLY_INFEASIBLE
            "test_conic_NormInfinityCone_INFEASIBLE",
            "test_conic_NormOneCone_INFEASIBLE",
            "test_conic_linear_INFEASIBLE",
            "test_linear_INFEASIBLE",
            # TODO(odow): implement
            "test_attribute_SolverVersion",
            # Uno does not support integrality
            "Indicator",
            r"[Ii]nteger",
            "Semicontinuous",
            "Semiinteger",
            "SOS1",
            "SOS2",
            "ZeroOne",
            "test_cpsat_",
            # Existing MOI issues
            "test_nonlinear_invalid",
            "test_basic_VectorNonlinearFunction_",
        ],
    )
    return
end

function test_show()
    @test sprint(show, AmplNLWriter.Optimizer()) == "An AMPL (.nl) model"
    return
end

function test_name()
    model = AmplNLWriter.Optimizer()
    @test MOI.supports(model, MOI.Name())
    MOI.set(model, MOI.Name(), "Foo")
    @test MOI.get(model, MOI.Name()) == "Foo"
    return
end

function test_show()
    @test sprint(show, AmplNLWriter.Optimizer()) == "An AMPL (.nl) model"
    return
end

function test_solver_name()
    @test MOI.get(ipopt_optimizer(), MOI.SolverName()) == "AmplNLWriter"
    return
end

function test_abstractoptimizer()
    @test ipopt_optimizer() isa MOI.AbstractOptimizer
    return
end

function test_bad_string()
    model = ipopt_optimizer("bad_solver")
    x = MOI.add_variable(model)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OTHER_ERROR
    @test occursin("IOError", MOI.get(model, MOI.RawStatusString()))
    return
end

function test_function_constant_nonzero()
    model = ipopt_optimizer()
    x = MOI.add_variable(model)
    f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 1.0)
    MOI.add_constraint(model, f, MOI.GreaterThan(3.0))
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    @test isapprox(MOI.get(model, MOI.VariablePrimal(), x), 2.0, atol = 1e-6)
    @test isapprox(MOI.get(model, MOI.ObjectiveValue()), 3.0, atol = 1e-6)
    return
end

function test_raw_parameter()
    model = AmplNLWriter.Optimizer()
    attr = MOI.RawOptimizerAttribute("print_level")
    @test MOI.supports(model, attr)
    @test MOI.get(model, attr) === nothing
    MOI.set(model, attr, 0)
    @test MOI.get(model, attr) == 0
    return
end

function test_io()
    io = IOBuffer()
    model = ipopt_optimizer(; stdin = stdin, stdout = io)
    MOI.set(model, MOI.RawOptimizerAttribute("print_level"), 1)
    x = MOI.add_variable(model)
    MOI.add_constraint(model, x, MOI.GreaterThan(0.0))
    MOI.optimize!(model)
    flush(io)
    seekstart(io)
    s = String(take!(io))
    if Sys.iswindows()
        @test length(s) >= 0
    else
        @test length(s) > 0
    end
    return
end

function test_single_variable_interval_dual()
    model = ipopt_optimizer()
    x = MOI.add_variable(model)
    c = MOI.add_constraint(model, x, MOI.Interval(0.0, 1.0))
    f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 2.0)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.optimize!(model)
    @test isapprox(MOI.get(model, MOI.ConstraintDual(), c), -1, atol = 1e-6)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    @test isapprox(MOI.get(model, MOI.ConstraintDual(), c), 1, atol = 1e-6)
    return
end

function test_nlpblockdual()
    model = ipopt_optimizer()
    v = MOI.add_variables(model, 4)
    l = [1.1, 1.2, 1.3, 1.4]
    u = [5.1, 5.2, 5.3, 5.4]
    start = [2.1, 2.2, 2.3, 2.4]
    MOI.add_constraint.(model, v, MOI.GreaterThan.(l))
    MOI.add_constraint.(model, v, MOI.LessThan.(u))
    MOI.set.(model, MOI.VariablePrimalStart(), v, start)
    lb, ub = [25.0, 40.0], [Inf, 40.0]
    evaluator = MOI.Test.HS071(true)
    block_data = MOI.NLPBlockData(MOI.NLPBoundsPair.(lb, ub), evaluator, true)
    MOI.set(model, MOI.NLPBlock(), block_data)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    dual = MOI.get(model, MOI.NLPBlockDual())
    @test isapprox(dual, [0.1787618002239518, 0.9850008232874167], atol = 1e-6)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.optimize!(model)
    dual = MOI.get(model, MOI.NLPBlockDual())
    @test isapprox(dual, [0.0, -5.008488314902599], atol = 1e-6)
    return
end

function test_AbstractSolverCommand()
    cmd = AmplNLWriter._DefaultSolverCommand(f -> f())
    model = AmplNLWriter.Optimizer(cmd)
    @test model.solver_command === cmd
    return
end

function test_solve_time()
    model = ipopt_optimizer()
    @test isnan(MOI.get(model, MOI.SolveTimeSec()))
    v = MOI.add_variables(model, 4)
    l = [1.1, 1.2, 1.3, 1.4]
    u = [5.1, 5.2, 5.3, 5.4]
    start = [2.1, 2.2, 2.3, 2.4]
    MOI.add_constraint.(model, v, MOI.GreaterThan.(l))
    MOI.add_constraint.(model, v, MOI.LessThan.(u))
    MOI.set.(model, MOI.VariablePrimalStart(), v, start)
    lb, ub = [25.0, 40.0], [Inf, 40.0]
    evaluator = MOI.Test.HS071(true)
    block_data = MOI.NLPBlockData(MOI.NLPBoundsPair.(lb, ub), evaluator, true)
    MOI.set(model, MOI.NLPBlock(), block_data)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.SolveTimeSec()) > 0.0
    return
end

function test_directory()
    temp_dir = mktempdir()
    model = ipopt_optimizer(; directory = temp_dir)
    v = MOI.add_variables(model, 4)
    l = [1.1, 1.2, 1.3, 1.4]
    u = [5.1, 5.2, 5.3, 5.4]
    start = [2.1, 2.2, 2.3, 2.4]
    MOI.add_constraint.(model, v, MOI.GreaterThan.(l))
    MOI.add_constraint.(model, v, MOI.LessThan.(u))
    MOI.set.(model, MOI.VariablePrimalStart(), v, start)
    lb, ub = [25.0, 40.0], [Inf, 40.0]
    evaluator = MOI.Test.HS071(true)
    block_data = MOI.NLPBlockData(MOI.NLPBoundsPair.(lb, ub), evaluator, true)
    MOI.set(model, MOI.NLPBlock(), block_data)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.optimize!(model)
    @test isfile(joinpath(temp_dir, "model.nl"))
    @test isfile(joinpath(temp_dir, "model.sol"))
    return
end

function test_no_sol_file()
    model = ipopt_optimizer()
    x = MOI.add_variable(model)
    MOI.add_constraint(model, x, MOI.GreaterThan(2.0))
    MOI.add_constraint(model, x, MOI.LessThan(1.0))
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OTHER_ERROR
    @test occursin(
        "The solver executed normally, but no `.sol` file was created",
        MOI.get(model, MOI.RawStatusString()),
    )
    return
end

function test_supports_incremental_interface()
    model = AmplNLWriter.Optimizer()
    @test !MOI.supports_incremental_interface(model)
    return
end

end  # module

TestMOIWrapper.runtests()
