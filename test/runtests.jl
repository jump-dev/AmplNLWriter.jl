using Test

if VERSION < v"1.3"
    import Ipopt
    run_with_ampl(f) = f(Ipopt.amplexe)
else
    import Ipopt_jll
    run_with_ampl(f) = Ipopt_jll.amplexe(f)
end

@testset "MOI" begin
    include("MOI_wrapper.jl")
end

@testset "Base" begin
    include("nl_convert.jl")
    include("nl_linearity.jl")
    include("nl_write.jl")
    include("sol_file_parser.jl")
end
