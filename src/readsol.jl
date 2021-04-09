"""
    _interpret_status(solve_result_num::Int, raw_status_string::String)

Convert the `solve_result_num` and `raw_status_string` into MOI-type statuses.

For the primal status, assume a solution is present. Other code is responsible
for returning `MOI.NO_SOLUTION` if no primal solution is present.
"""
function _interpret_status(solve_result_num::Int, raw_status_string::String)
    if 0 <= solve_result_num < 100
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT
    elseif 100 <= solve_result_num < 200
        return MOI.LOCALLY_SOLVED, MOI.UNKNOWN_RESULT_STATUS
    elseif 200 <= solve_result_num < 300
        return MOI.INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif 300 <= solve_result_num < 400
        return MOI.DUAL_INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif 400 <= solve_result_num < 500
        return MOI.OTHER_LIMIT, MOI.UNKNOWN_RESULT_STATUS
    elseif 500 <= solve_result_num < 600
        return MOI.OTHER_ERROR, MOI.UNKNOWN_RESULT_STATUS
    end
    # If we didn't get a valid solve_result_num, try to get the status from the
    # solve_message string. Some solvers (e.g. SCIP) don't ever print the
    # suffixes so we need this.
    message = lowercase(raw_status_string)
    if occursin("optimal", message)
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT
    elseif occursin("infeasible", message)
        return MOI.INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif occursin("unbounded", message)
        return MOI.DUAL_INFEASIBLE, MOI.UNKNOWN_RESULT_STATUS
    elseif occursin("limit", message)
        return MOI.OTHER_LIMIT, MOI.UNKNOWN_RESULT_STATUS
    elseif occursin("error", message)
        return MOI.OTHER_ERROR, MOI.UNKNOWN_RESULT_STATUS
    else
        return MOI.OTHER_ERROR, MOI.UNKNOWN_RESULT_STATUS
    end
end

struct _NLResults
    raw_status_string::String
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    objective_value::Float64
    primal_solution::Dict{MOI.VariableIndex,Float64}
end

function _readline(io::IO)
    if eof(io)
        error("Reached end of sol file unexpectedly.")
    end
    return strip(readline(io))
end
_readline(io::IO, T) = parse(T, _readline(io))

function _read_sol(filename::String, model::_NLModel)
    return open(io -> _read_sol(io, model), filename, "r")
end

"""
    _read_sol(io::IO, model::_NLModel)

This function is based on a Julia translation of readsol.c, available at
https://github.com/ampl/asl/blob/64919f75fa7a438f4b41bce892dcbe2ae38343ee/src/solvers/readsol.c
and under the following license:

Copyright (C) 2017 AMPL Optimization, Inc.; written by David M. Gay.
Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted,
provided that the above copyright notice appear in all copies and that
both that the copyright notice and this permission notice and warranty
disclaimer appear in supporting documentation.

The author and AMPL Optimization, Inc. disclaim all warranties with
regard to this software, including all implied warranties of
merchantability and fitness.  In no event shall the author be liable
for any special, indirect or consequential damages or any damages
whatsoever resulting from loss of use, data or profits, whether in an
action of contract, negligence or other tortious action, arising out
of or in connection with the use or performance of this software.
"""
function _read_sol(io::IO, model::_NLModel)
    raw_status_string = ""
    line = ""
    while !startswith(line, "Options")
        line = _readline(io)
        raw_status_string *= line
    end
    # Read through all the options. Direct copy of reference implementation.
    @assert startswith(line, "Options")
    options = [_readline(io, Int), _readline(io, Int), _readline(io, Int)]
    num_options = options[1]
    if !(3 <= num_options <= 9)
        error("expected num_options between 3 and 9; " * "got $num_options")
    end
    need_vbtol = false
    if options[3] == 3
        num_options -= 2
        need_vbtol = true
    end
    for j in 3:num_options
        push!(options, _readline(io, Int))
    end
    # Read number of constraints
    num_cons = _readline(io, Int)
    @assert(num_cons == length(model.g) + length(model.h))
    # Read number of dual solutions to read in
    num_duals_to_read = _readline(io, Int)
    @assert(num_duals_to_read == 0 || num_duals_to_read == num_cons)
    # Read number of variables
    num_vars = _readline(io, Int)
    @assert(num_vars == length(model.x))
    # Read number of primal solutions to read in
    num_vars_to_read = _readline(io, Int)
    @assert(num_vars_to_read == 0 || num_vars_to_read == num_vars)
    # Skip over vbtol line if present
    if need_vbtol
        _readline(io)
    end
    # Read dual solutions
    # TODO(odow): read in the dual solutions!
    for _ in 1:num_duals_to_read
        _readline(io)
    end
    # Read primal solutions
    primal_solution = Dict{MOI.VariableIndex,Float64}()
    if num_vars_to_read > 0
        for xi in model.order
            primal_solution[xi] = _readline(io, Float64)
        end
    end
    # Check for status code
    solve_result_num = -1
    while !eof(io)
        linevals = split(_readline(io), " ")
        if length(linevals) > 0 && linevals[1] == "objno"
            @assert parse(Int, linevals[2]) == 0
            solve_result_num = parse(Int, linevals[3])
            break
        end
    end
    termination_status, primal_status =
        _interpret_status(solve_result_num, raw_status_string)
    objective_value = NaN
    if length(primal_solution) > 0
        # TODO(odow): is there a better way of getting this other than
        # evaluating it?
        objective_value = _evaluate(model.f, primal_solution)
    end
    return _NLResults(
        raw_status_string,
        termination_status,
        length(primal_solution) > 0 ? primal_status : MOI.NO_SOLUTION,
        objective_value,
        primal_solution,
    )
end
