using AmplNLWriter, Test

@testset "MOI" begin
    include("MOI_wrapper.jl")
end

@testset "Base" begin
    include("nl_convert.jl")
    include("nl_linearity.jl")
    include("nl_write.jl")
    include("sol_file_parser.jl")
end
