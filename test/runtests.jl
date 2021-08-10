if get(ENV, "GITHUB_ACTIONS", "") == "true"
    import Pkg
    Pkg.add(Pkg.PackageSpec(name = "MathOptInterface", rev = "master"))
    Pkg.add(Pkg.PackageSpec(name = "Ipopt", rev = "od/moi10"))
end

using Test

@testset "MOI_wrapper" begin
    include("MOI_wrapper.jl")
end
