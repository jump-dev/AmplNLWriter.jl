using AmplNLWriter, Ipopt

import MathOptInterface
const MOI = MathOptInterface
const MOIT = MOI.Test

const optimizer = AmplNLWriter.Optimizer(Ipopt.amplexe, ["print_level = 0"])

const config = MOIT.TestConfig(
    atol = 1e-4, rtol = 1e-4, optimal_status = MOI.LOCALLY_SOLVED
)

@testset "MOI NLP tests" begin
    MOIT.nlptest(optimizer, config)
end
