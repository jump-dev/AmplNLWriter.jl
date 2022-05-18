# Copyright (c) 2015: AmplNLWriter.jl contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import Pkg
Pkg.add(Pkg.PackageSpec(;name = "MathOptInterface", rev = "od/nl-sol"))

using Test

@testset "MOI_wrapper" begin
    include("MOI_wrapper.jl")
end
