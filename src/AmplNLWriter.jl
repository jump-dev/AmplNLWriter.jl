__precompile__()
module AmplNLWriter

using MathProgBase
importall MathProgBase.SolverInterface

debug = false
setdebug(b::Bool) = global debug = b

solverdata_dir = joinpath(Pkg.dir("AmplNLWriter"), ".solverdata")

include("nl_linearity.jl")
include("nl_params.jl")
include("nl_convert.jl")

export AmplNLSolver,
       getsolvername, getsolveresult, getsolveresultnum, getsolvemessage,
       getsolveexitcode

immutable AmplNLSolver <: AbstractMathProgSolver
    solver_command::String
    options::Vector{String}
    filename::String
end

function AmplNLSolver(solver_command::String,
                      options::Vector{String}=String[];
                      filename::String="")
    AmplNLSolver(solver_command, options, filename)
end

function BonminNLSolver(options=String[]; filename::String="")
    error("""
        BonminNLSolver is no longer available by default through AmplNLWriter.

        You should install CoinOptServices via

            Pkg.add("CoinOptServices")

        and then replace BonminNLSolver(options=String[]; filename::String="")
        with

            AmplNLWriter(CoinOptServices.bonmin, options; filename=filename)

    """)
end

function CouenneNLSolver(options=String[]; filename::String="")
    error("""
        CouenneNLSolver is no longer available by default through AmplNLWriter.

        You should install CoinOptServices via

            Pkg.add("CoinOptServices")

        and then replace CouenneNLSolver(options=String[]; filename::String="")
        with

            AmplNLWriter(CoinOptServices.couenne, options; filename=filename)

    """)
end

function IpoptNLSolver(options=String[]; filename::String="")
    error("""
        CouenneNLSolver is no longer available by default through AmplNLWriter.

        You should install Ipopt via

            Pkg.add("Ipopt")

        and then replace IpoptNLSolver(options=String[]; filename::String="")
        with

            AmplNLWriter(Ipopt.amplexe, options; filename=filename)

    """)
end

getsolvername(s::AmplNLSolver) = basename(s.solver_command)

type AmplNLMathProgModel <: AbstractMathProgModel
    options::Vector{String}

    solver_command::String

    x_l::Vector{Float64}
    x_u::Vector{Float64}
    g_l::Vector{Float64}
    g_u::Vector{Float64}

    nvar::Int
    ncon::Int

    obj
    constrs::Vector{Any}

    lin_constrs::Vector{Dict{Int, Float64}}
    lin_obj::Dict{Int, Float64}

    r_codes::Vector{Int}
    j_counts::Vector{Int}

    vartypes::Vector{Symbol}
    varlinearities_con::Vector{Symbol}
    varlinearities_obj::Vector{Symbol}
    conlinearities::Vector{Symbol}
    objlinearity::Symbol

    v_index_map::Dict{Int, Int}
    v_index_map_rev::Dict{Int, Int}
    c_index_map::Dict{Int, Int}
    c_index_map_rev::Dict{Int, Int}

    sense::Symbol

    x_0::Vector{Float64}

    file_basename::String
    probfile::String
    solfile::String

    objval::Float64
    solution::Vector{Float64}

    status::Symbol
    solve_exitcode::Int
    solve_result_num::Int
    solve_result::String
    solve_message::String
    solve_time::Float64

    d::AbstractNLPEvaluator

    function AmplNLMathProgModel(solver_command::String,
                                 options::Vector{String},
                                 filename::String)
        new(options,
            solver_command,
            zeros(0),
            zeros(0),
            zeros(0),
            zeros(0),
            0,
            0,
            :(0),
            [],
            Dict{Int, Float64}[],
            Dict{Int, Float64}(),
            Int[],
            Int[],
            Symbol[],
            Symbol[],
            Symbol[],
            Symbol[],
            :Lin,
            Dict{Int, Int}(),
            Dict{Int, Int}(),
            Dict{Int, Int}(),
            Dict{Int, Int}(),
            :Min,
            zeros(0),
            filename,
            "",
            "",
            NaN,
            zeros(0),
            :NotSolved,
            -1,
            -1,
            "?",
            "",
            NaN)
    end
end
type AmplNLLinearQuadraticModel <: AbstractLinearQuadraticModel
    inner::AmplNLMathProgModel
end
type AmplNLNonlinearModel <: AbstractNonlinearModel
    inner::AmplNLMathProgModel
end

include("nl_write.jl")

NonlinearModel(s::AmplNLSolver) = AmplNLNonlinearModel(
    AmplNLMathProgModel(s.solver_command, s.options, s.filename)
)
LinearQuadraticModel(s::AmplNLSolver) = AmplNLLinearQuadraticModel(
    AmplNLMathProgModel(s.solver_command, s.options, s.filename)
)

function loadproblem!(outer::AmplNLNonlinearModel, nvar::Integer, ncon::Integer,
                      x_l, x_u, g_l, g_u, sense::Symbol,
                      d::AbstractNLPEvaluator)
    m = outer.inner

    m.nvar, m.ncon = nvar, ncon
    loadcommon!(m, x_l, x_u, g_l, g_u, sense)

    m.d = d
    initialize(m.d, [:ExprGraph])

    # Process constraints
    m.constrs = map(1:m.ncon) do i
        c = constr_expr(m.d, i)

        # Remove relations and bounds from constraint expressions
        if length(c.args) == 3
            if VERSION < v"0.5-"
                expected_head = :comparison
                expr_index = 1
                rel_index = 2
            else
                expected_head = :call
                expr_index = 2
                rel_index = 1
            end

            @assert c.head == expected_head
            # Single relation constraint: expr rel bound
            rel = c.args[rel_index]
            m.r_codes[i] = relation_to_nl[rel]
            if rel == [:<=, :(==)]
                m.g_u[i] = c.args[3]
            end
            if rel in [:>=, :(==)]
                m.g_l[i] = c.args[3]
            end
            c = c.args[expr_index]
        else
            # Double relation constraint: bound <= expr <= bound
            @assert c.head == :comparison
            m.r_codes[i] = relation_to_nl[:multiple]
            m.g_u[i] = c.args[5]
            m.g_l[i] = c.args[1]
            c = c.args[3]
        end

        # Convert non-linear expression to non-linear, linear and constant
        c, constant, m.conlinearities[i] = process_expression!(
            c, m.lin_constrs[i], m.varlinearities_con)

        # Update bounds on constraint
        m.g_l[i] -= constant
        m.g_u[i] -= constant

        # Update jacobian counts using the linear constraint variables
        for j in keys(m.lin_constrs[i])
            m.j_counts[j] += 1
        end
        c
    end

    # Process objective
    m.obj = obj_expr(m.d)
    if length(m.obj.args) < 2
        m.obj = 0
    else
        # Convert non-linear expression to non-linear, linear and constant
        m.obj, constant, m.objlinearity = process_expression!(
            m.obj, m.lin_obj, m.varlinearities_obj)

        # Add constant back into non-linear expression
        if constant != 0
            m.obj = add_constant(m.obj, constant)
        end
    end
    m
end

function loadproblem!(outer::AmplNLLinearQuadraticModel, A::AbstractMatrix,
                      x_l, x_u, c, g_l, g_u, sense)
    m = outer.inner
    m.ncon, m.nvar = size(A)

    loadcommon!(m, x_l, x_u, g_l, g_u, sense)

    # Load A into the linear constraints
    @assert (m.ncon, m.nvar) == size(A)
    load_A!(m, A)
    m.constrs = zeros(m.ncon)  # Dummy constraint expression trees

    # Load c
    for (index, val) in enumerate(c)
        m.lin_obj[index] = val
    end
    m.obj = 0  # Dummy objective expression tree

    # Process variables bounds
    for j = 1:m.ncon
        lower = m.g_l[j]
        upper = m.g_u[j]
        if lower == -Inf
            if upper == Inf
                error("Neither lower nor upper bound on constraint $j")
            else
                m.r_codes[j] = 1
            end
        else
            if lower == upper
                m.r_codes[j] = 4
            elseif upper == Inf
                m.r_codes[j] = 2
            else
                m.r_codes[j] = 0
            end
        end
    end
    m
end

function load_A!(m::AmplNLMathProgModel, A::SparseMatrixCSC{Float64})
    for var = 1:A.n, k = A.colptr[var] : (A.colptr[var + 1] - 1)
        m.lin_constrs[A.rowval[k]][var] = A.nzval[k]
        m.j_counts[var] += 1
    end
end

function load_A!(m::AmplNLMathProgModel, A::Matrix{Float64})
    for con = 1:m.ncon, var = 1:m.nvar
        val = A[con, var]
        if val != 0
            m.lin_constrs[con][var] = val
            m.j_counts[var] += 1
        end
    end
end

function loadcommon!(m::AmplNLMathProgModel, x_l, x_u, g_l, g_u, sense)
    @assert m.nvar == length(x_l) == length(x_u)
    @assert m.ncon == length(g_l) == length(g_u)

    m.x_l, m.x_u = x_l, x_u
    m.g_l, m.g_u = g_l, g_u
    setsense!(m, sense)

    m.lin_constrs = [Dict{Int, Float64}() for _ in 1:m.ncon]
    m.j_counts = zeros(Int, m.nvar)

    m.r_codes = Array{Int}(m.ncon)

    m.varlinearities_con = fill(:Lin, m.nvar)
    m.varlinearities_obj = fill(:Lin, m.nvar)
    m.conlinearities = fill(:Lin, m.ncon)
    m.objlinearity = :Lin

    m.vartypes = fill(:Cont, m.nvar)
    m.x_0 = zeros(m.nvar)
end

getvartype(m::AmplNLMathProgModel) = copy(m.vartypes)
function setvartype!(m::AmplNLMathProgModel, cat::Vector{Symbol})
    @assert all(x-> (x in [:Cont,:Bin,:Int]), cat)
    m.vartypes = copy(cat)
end

getsense(m::AmplNLMathProgModel) = m.sense
function setsense!(m::AmplNLMathProgModel, sense::Symbol)
    @assert sense == :Min || sense == :Max
    m.sense = sense
end

setwarmstart!(m::AmplNLMathProgModel, v::Vector{Float64}) = m.x_0 = v

function optimize!(m::AmplNLMathProgModel)
    m.status = :NotSolved
    m.solve_exitcode = -1
    m.solve_result_num = -1
    m.solve_result = "?"
    m.solve_message = ""

    # There is no non-linear binary type, only non-linear discrete, so make
    # sure binary vars have bounds in [0, 1]
    for i in 1:m.nvar
        if m.vartypes[i] == :Bin
            if m.x_l[i] < 0
                m.x_l[i] = 0
            end
            if m.x_u[i] > 1
                m.x_u[i] = 1
            end
        end
    end

    make_var_index!(m)
    make_con_index!(m)

    if length(m.file_basename) == 0
        # No filename specified - write to a randomly named file
        file_basepath, f_prob = mktemp(solverdata_dir)
    else
        file_basepath = joinpath(solverdata_dir, "$(m.file_basename)")
        f_prob = open(file_basepath, "w")
    end
    m.probfile = "$file_basepath.nl"
    m.solfile = "$file_basepath.sol"

    write_nl_file(f_prob, m)
    close(f_prob)

    # Rename file to have .nl extension (this is required by solvers)
    # remove_destination flag added to fix issue in Windows, where temp file are not absolutely unique and file closing is not fast enough
    # See https://github.com/JuliaOpt/AmplNLWriter.jl/pull/63.
    mv(file_basepath, m.probfile, remove_destination=true)

    # Run solver and save exitcode
    t = time()
    proc = spawn(pipeline(
        `$(m.solver_command) $(m.probfile) -AMPL $(m.options)`, stdout=STDOUT))
    wait(proc)
    kill(proc)
    m.solve_exitcode = proc.exitcode
    m.solve_time = time() - t

    if m.solve_exitcode == 0
        read_results(m)
    else
        m.status = :Error
        m.solution = fill(NaN,m.nvar)
        m.solve_result = "failure"
        m.solve_result_num = 999
    end

    # Clean up temp files
    if !debug
        for temp_file in [m.probfile; m.solfile]
            isfile(temp_file) && rm(temp_file)
        end
    end
end

function process_expression!(nonlin_expr::Expr, lin_expr::Dict{Int, Float64},
                             varlinearities::Vector{Symbol})
    # Get list of all variables in the expression
    extract_variables!(lin_expr, nonlin_expr)
    # Extract linear and constant terms from non-linear expression
    tree = LinearityExpr(nonlin_expr)
    tree = pull_up_constants(tree)
    _, tree, constant = prune_linear_terms!(tree, lin_expr)
    # Make sure all terms remaining in the tree are .nl-compatible
    nonlin_expr = convert_formula(tree)

    # Track which variables appear nonlinearly
    nonlin_vars = Dict{Int, Float64}()
    extract_variables!(nonlin_vars, nonlin_expr)
    for j in keys(nonlin_vars)
        varlinearities[j] = :Nonlin
    end

    # Remove variables at coeff 0 that aren't also in the nonlinear tree
    for (j, coeff) in lin_expr
        if coeff == 0 && !(j in keys(nonlin_vars))
            delete!(lin_expr, j)
        end
    end

    # Mark constraint as nonlinear if anything is left in the tree
    linearity = nonlin_expr != 0 ? :Nonlin : :Lin

    return nonlin_expr, constant, linearity
end
function process_expression!(nonlin_expr::Real, lin_expr, varlinearities)
    # Special case where body of constraint is constant
    # Return empty nonlinear and linear parts, and use the body as the constant
    0, nonlin_expr, :Lin
end

status(m::AmplNLMathProgModel) = m.status
getsolution(m::AmplNLMathProgModel) = copy(m.solution)
getobjval(m::AmplNLMathProgModel) = m.objval
numvar(m::AmplNLMathProgModel) = m.nvar
numconstr(m::AmplNLMathProgModel) = m.ncon
getsolvetime(m::AmplNLMathProgModel) = m.solve_time

# Access to AMPL solve result items
get_solve_result(m::AmplNLMathProgModel) = m.solve_result
get_solve_result_num(m::AmplNLMathProgModel) = m.solve_result_num
get_solve_message(m::AmplNLMathProgModel) = m.solve_message
get_solve_exitcode(m::AmplNLMathProgModel) = m.solve_exitcode

# We need to track linear coeffs of all variables present in the expression tree
extract_variables!(lin_constr::Dict{Int, Float64}, c) = c
extract_variables!(lin_constr::Dict{Int, Float64}, c::LinearityExpr) =
    extract_variables!(lin_constr, c.c)
function extract_variables!(lin_constr::Dict{Int, Float64}, c::Expr)
    if c.head == :ref
        if c.args[1] == :x
            @assert isa(c.args[2], Int)
            lin_constr[c.args[2]] = 0
        else
            error("Unrecognized reference expression $c")
        end
    else
        map(arg -> extract_variables!(lin_constr, arg), c.args)
    end
end

add_constant(c, constant::Real) = c + constant
add_constant(c::Expr, constant::Real) = Expr(:call, :+, c, constant)

function make_var_index!(m::AmplNLMathProgModel)
    nonlin_cont = Int[]
    nonlin_int = Int[]
    lin_cont = Int[]
    lin_int = Int[]
    lin_bin = Int[]

    for i in 1:m.nvar
        if m.varlinearities_obj[i] == :Nonlin ||
           m.varlinearities_con[i] == :Nonlin
            if m.vartypes[i] == :Cont
                push!(nonlin_cont, i)
            else
                push!(nonlin_int, i)
            end
        else
            if m.vartypes[i] == :Cont
                push!(lin_cont, i)
            elseif m.vartypes[i] == :Int
                push!(lin_int, i)
            else
                push!(lin_bin, i)
            end
        end
    end

    # Index variables in required order
    for var_list in (nonlin_cont, nonlin_int, lin_cont, lin_bin, lin_int)
        add_to_index_maps!(m.v_index_map, m.v_index_map_rev, var_list)
    end
end

function make_con_index!(m::AmplNLMathProgModel)
    nonlin_cons = Int[]
    lin_cons = Int[]

    for i in 1:m.ncon
        if m.conlinearities[i] == :Nonlin
            push!(nonlin_cons, i)
        else
            push!(lin_cons, i)
        end
    end
    for con_list in (nonlin_cons, lin_cons)
        add_to_index_maps!(m.c_index_map, m.c_index_map_rev, con_list)
    end
end

function add_to_index_maps!(forward_map::Dict{Int, Int},
                            backward_map::Dict{Int, Int},
                            inds::Array{Int})
    for i in inds
        # Indices are 0-prefixed so the next index is the current dict length
        index = length(forward_map)
        forward_map[i] = index
        backward_map[index] = i
    end
end

function read_results(m::AmplNLMathProgModel)
    open(m.solfile, "r")do io
        read_results(io, m)
    end
end

function read_results(resultio, m::AmplNLMathProgModel)
    did_read_solution = read_sol(resultio, m)

    # Convert solve_result
    if 0 <= m.solve_result_num < 100
        m.status = :Optimal
        m.solve_result = "solved"
    elseif 100 <= m.solve_result_num < 200
        # Used to indicate solution present but likely incorrect.
        m.status = :Optimal
        m.solve_result = "solved?"
        warn("The solver has returned the status :Optimal, but indicated that there might be an error in the solution. The status code returned by the solver was $(m.solve_result_num). Check the solver documentation for more info.""")
    elseif 200 <= m.solve_result_num < 300
        m.status = :Infeasible
        m.solve_result = "infeasible"
    elseif 300 <= m.solve_result_num < 400
        m.status = :Unbounded
        m.solve_result = "unbounded"
    elseif 400 <= m.solve_result_num < 500
        m.status = :UserLimit
        m.solve_result = "limit"
    elseif 500 <= m.solve_result_num < 600
        m.status = :Error
        m.solve_result = "failure"
    end

    # If we didn't get a valid solve_result_num, try to get the status from the
    # solve_message string.
    # Some solvers (e.g. SCIP) don't ever print the suffixes so we need this.
    if m.status == :NotSolved
        message = lowercase(m.solve_message)
        if contains(message, "optimal")
            m.status = :Optimal
        elseif contains(message, "infeasible")
            m.status = :Infeasible
        elseif contains(message, "unbounded")
            m.status = :Unbounded
        elseif contains(message, "limit")
            m.status = :UserLimit
        elseif contains(message, "error")
            m.status = :Error
        end
    end

    if did_read_solution
        if m.objlinearity == :Nonlin
            # Try to use NLPEvaluator if we can.
            # Can fail due to unsupported functions so fallback to eval
            try
                m.objval = eval_f(m.d, m.solution)
                return
            end
        end

        # Calculate objective value from nonlinear and linear parts
        obj_nonlin = eval(substitute_vars!(deepcopy(m.obj), m.solution))
        obj_lin = evaluate_linear(m.lin_obj, m.solution)
        m.objval = obj_nonlin + obj_lin
    end
end

function read_sol(m::AmplNLMathProgModel)
    open(m.solfile, "r")do io
        readsol(io, m)
    end
end

function read_sol(f::IO, m::AmplNLMathProgModel)
    # Reference implementation:
    # https://github.com/ampl/mp/tree/master/src/asl/solvers/readsol.c
    stat = :Undefined
    line = ""

    # Keep building solver message by reading until first truly empty line
    while true
        line = readline(f)
        isempty(chomp(line)) && break
        m.solve_message *= line
    end

    # Skip over empty lines
    while true
        line = readline(f)
        !isempty(chomp(line)) && break
    end

    # Read through all the options. Direct copy of reference implementation.
    @assert line[1:7] == "Options"
    options = [parse(Int, chomp(readline(f))) for _ in 1:3]
    num_options = options[1]
    3 <= num_options <= 9 || error("expected num_options between 3 and 9; " *
                                   "got $num_options")
    need_vbtol = false
    if options[3] == 3
        num_options -= 2
        need_vbtol = true
    end
    for j = 3:num_options
        eof(f) && error()
        push!(options, parse(Int, chomp(readline(f))))
    end

    # Read number of constraints
    num_cons = parse(Int, chomp(readline(f)))
    @assert(num_cons == m.ncon)

    # Read number of duals to read in
    num_duals_to_read = parse(Int, chomp(readline(f)))
    @assert(num_duals_to_read in [0; m.ncon])

    # Read number of variables
    num_vars = parse(Int, chomp(readline(f)))
    @assert(num_vars == m.nvar)

    # Read number of variables to read in
    num_vars_to_read = parse(Int, chomp(readline(f)))
    @assert(num_vars_to_read in [0; m.nvar])

    # Skip over vbtol line if present
    need_vbtol && readline(f)

    # Skip over duals
    # TODO do something with these?
    for index in 0:(num_duals_to_read - 1)
        eof(f) && error("End of file while reading duals.")
        line = readline(f)
    end

    # Next, read for the variable values
    x = fill(NaN, m.nvar)
    m.objval = NaN
    for index in 0:(num_vars_to_read - 1)
        eof(f) && error("End of file while reading variables.")
        line = readline(f)

        i = m.v_index_map_rev[index]
        x[i] = float(chomp(line))
    end
    m.solution = x

    # Check for status code
    while !eof(f)
        line = readline(f)
        linevals = split(chomp(line), " ")
        num_vals = length(linevals)
        if num_vals > 0 && linevals[1] == "objno"
            # Check for objno == 0
            @assert parse(Int, linevals[2]) == 0
            # Get solve_result
            m.solve_result_num = parse(Int, linevals[3])

            # We can stop looking for the 'objno' line
            break
        end
    end
    return num_vars_to_read > 0
end

substitute_vars!(c, x::Array{Float64}) = c
function substitute_vars!(c::Expr, x::Array{Float64})
    if c.head == :ref
        if c.args[1] == :x
            index = c.args[2]
            @assert isa(index, Int)
            c = x[index]
        else
            error("Unrecognized reference expression $c")
        end
    else
        if c.head == :call
            # Convert .nl unary minus (:neg) back to :-
            if c.args[1] == :neg
                c.args[1] = :-
            # Convert .nl :sum back to :+
            elseif c.args[1] == :sum
                c.args[1] = :+
            end
        end
        map!(arg -> substitute_vars!(arg, x), c.args, c.args)
    end
    c
end

function evaluate_linear(linear_coeffs::Dict{Int, Float64}, x::Array{Float64})
    total = 0.0
    for (i, coeff) in linear_coeffs
        total += coeff * x[i]
    end
    total
end

# Wrapper functions
for f in [:getvartype,:getsense,:optimize!,:status,:getsolution,:getobjval,:numvar,:numconstr,:get_solve_result,:get_solve_result_num,:get_solve_message,:get_solve_exitcode,:getsolvetime]
    @eval $f(m::AmplNLNonlinearModel) = $f(m.inner)
    @eval $f(m::AmplNLLinearQuadraticModel) = $f(m.inner)
end
for f in [:setvartype!,:setsense!,:setwarmstart!]
    @eval $f(m::AmplNLNonlinearModel, x) = $f(m.inner, x)
    @eval $f(m::AmplNLLinearQuadraticModel, x) = $f(m.inner, x)
end

# Utility method for deleting any leftover debug files
function clean_solverdata()
    for file in readdir(solverdata_dir)
        ext = splitext(file)[2]
        (ext == ".nl" || ext == ".sol") && rm(joinpath(solverdata_dir, file))
    end
end

end
