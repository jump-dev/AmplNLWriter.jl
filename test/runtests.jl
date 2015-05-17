using AmplNLWriter
using FactCheck

include("nl_convert.jl")
include("nl_linearity.jl")

examples_path = joinpath(dirname(dirname(@__FILE__)), "examples")
for example in readdir(examples_path)
    include(joinpath(examples_path, example))
end

FactCheck.exitstatus()
