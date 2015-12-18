function AmplNLSolver(solver_command::AbstractString,
                      options::Dict{ASCIIString,}=Dict{ASCIIString,}();
                      filename::AbstractString="")
  Base.warn_once("Specifying options with a Dict is deprecated. Use a Vector{ASCIIString} to specify options instead, e.g.,\n\tAmplNLSolver(\"/path/to/solver\", [\"option1=value1\";\"option2=value2\";...])")
  AmplNLSolver(solver_command, ["$key=$value" for (key, value) in options],
               filename=filename)
end
