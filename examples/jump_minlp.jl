using NL, JuMP

## Solve test problem 1 (Synthesis of processing system) in
 #  M. Duran & I.E. Grossmann, "An outer approximation algorithm for
 #  a class of mixed integer nonlinear programs", Mathematical
 #  Programming 36, pp. 307-339, 1986.  The problem also appears as
 #  problem synthes1 in the MacMINLP test set.
 #
 #  min   5 x4 + 6 x5 + 8 x6 + 10 x1 - 7 x3 -18 math.log(x2 + 1)
 #       - 19.2 math.log(x1 - x2 + 1) + 10
 #  s.t.  0.8 math.log(x2 + 1) + 0.96 math.log(x1 - x2 + 1) - 0.8 x3 >= 0
 #        math.log(x2 + 1) + 1.2 math.log(x1 - x2 + 1) - x3 - 2 x6 >= -2
 #        x2 - x1 <= 0
 #        x2 - 2 x4 <= 0
 #        x1 - x2 - 2 x5 <= 0
 #        x4 + x5 <= 1
 #        0 <= x1 <= 2
 #        0 <= x2 <= 2
 #        0 <= x3 <= 1
 #        x1, x2, x3 continuous
 #        x4, x5, x6 binary
 #
 #
 #  The solution is (1.30098, 0, 1, 0, 1, 0).
 ##

m = Model(solver=NLSolver())
x_U = [2,2,1]
@defVar(m, x_U[i] >= x[i=1:3] >= 0)
@defVar(m, y[4:6], Bin)

@setNLObjective(m, Min, 10 + 10*x[1] - 7*x[3] + 5*y[4] + 6*y[5] + 8*y[6] - 18*log(x[2]+1) - 19.2*log(x[1]-x[2]+1))
@addNLConstraint(m, 0.8*log(x[2] + 1) + 0.96*log(x[1] - x[2] + 1) - 0.8*x[3] >= 0)
@addNLConstraint(m, log(x[2] + 1) + 1.2*log(x[1] - x[2] + 1) - x[3] - 2*y[6] >= -2)
@addNLConstraint(m, x[2] - x[1] <= 0)
@addNLConstraint(m, x[2] - 2*y[4] <= 0)
@addNLConstraint(m, x[1] - x[2] - 2*y[5] <= 0)
@addNLConstraint(m, y[4] + y[5] <= 1)
solve(m)
