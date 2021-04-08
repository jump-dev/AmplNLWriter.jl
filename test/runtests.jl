using Test

@testset "NLModel" begin
    include("NLModel.jl")
end

@testset "MOI" begin
    include("MOI_wrapper.jl")
end
