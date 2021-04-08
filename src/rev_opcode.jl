"""
    _REV_OPCODES

This dictionary is manualy curated, based on the list of opcodes in `opcode.jl`.

The goal is to map Julia functions to their AMPL opcode equivalent.

Sometimes, there is ambiguity, such as the `:+`, which Julia uses for unary,
binary, and n-ary addition, while AMPL doesn't support unary addition, uses
OPPLUS for binary, and OPSUMLIST for n-ary. In these cases, introduce a
different symbol to disambiguate them in the context of this dictionary, and add
logic to `_process_call` to rewrite the Julia expression.

Commented out lines are opcodes supported by AMPL that don't have a clear Julia
equivalent. If you can think of one, feel free to add it.
"""
const _REV_OPCODES = Dict{Symbol,Int}(
    :+ => OPPLUS,  # binary-plus
    :- => OPMINUS,
    :* => OPMULT,
    :/ => OPDIV,
    :rem => OPREM,
    :^ => OPPOW,
    # OPLESS = 6
    :min => MINLIST,  # n-ary
    :max => MAXLIST,  # n-ary
    # FLOOR = 13
    # CEIL = 14
    :abs => ABS,
    :neg => OPUMINUS,
    :|| => OPOR,
    :&& => OPAND,
    :(<) => LT,
    :(<=) => LE,
    :(==) => EQ,
    :(>=) => GE,
    :(>) => GT,
    :(!=) => NE,
    :(!) => OPNOT,
    :ifelse => OPIFnl,
    :tanh => OP_tanh,
    :tan => OP_tan,
    :sqrt => OP_sqrt,
    :sinh => OP_sinh,
    :sin => OP_sin,
    :log10 => OP_log10,
    :log => OP_log,
    :exp => OP_exp,
    :cosh => OP_cosh,
    :cos => OP_cos,
    :atanh => OP_atanh,
    # OP_atan2 = 48,
    :atan => OP_atan,
    :asinh => OP_asinh,
    :asin => OP_asin,
    :acosh => OP_acosh,
    :acos => OP_acos,
    :sum => OPSUMLIST,  # n-ary plus
    # OPintDIV = 55
    # OPprecision = 56
    # OPround = 57
    # OPtrunc = 58
    # OPCOUNT = 59
    # OPNUMBEROF = 60
    # OPNUMBEROFs = 61
    # OPATLEAST = 62
    # OPATMOST = 63
    # OPPLTERM = 64
    # OPIFSYM = 65
    # OPEXACTLY = 66
    # OPNOTATLEAST = 67
    # OPNOTATMOST = 68
    # OPNOTEXACTLY = 69
    # ANDLIST = 70
    # ORLIST = 71
    # OPIMPELSE = 72
    # OP_IFF = 73
    # OPALLDIFF = 74
    # OPSOMESAME = 75
    # OP1POW = 76
    # OP2POW = 77
    # OPCPOW = 78
    # OPFUNCALL = 79
    # OPNUM = 80
    # OPHOL = 81
    # OPVARVAL = 82
    # N_OPS = 83
)

"""
    _OPCODES_EVAL
"""
const _OPCODES_EVAL = Dict{Int,Tuple{Int,Function}}(
    OPPLUS => (2, +),
    OPMINUS => (2, -),
    OPMULT => (2, *),
    OPDIV => (2, /),
    OPREM => (2, rem),
    OPPOW => (2, ^),
    # OPLESS = 6
    MINLIST => (-1, min),
    MAXLIST => (-1, max),
    # FLOOR = 13
    # CEIL = 14
    ABS => (1, abs),
    OPUMINUS => (1, -),
    OPOR => (2, |),
    OPAND => (2, &),
    LT => (2, <),
    LE => (2, <=),
    EQ => (2, ==),
    GE => (2, >=),
    GT => (2, >),
    NE => (2, !=),
    OPNOT => (1, !),
    OPIFnl => (3, ifelse),
    OP_tanh => (1, tanh),
    OP_tan => (1, tan),
    OP_sqrt => (1, sqrt),
    OP_sinh => (1, sinh),
    OP_sin => (1, sin),
    OP_log10 => (1, log10),
    OP_log => (1, log),
    OP_exp => (1, exp),
    OP_cosh => (1, cosh),
    OP_cos => (1, cos),
    OP_atanh => (1, atanh),
    # OP_atan2 = 48,
    OP_atan => (1, atan),
    OP_asinh => (1, asinh),
    OP_asin => (1, asin),
    OP_acosh => (1, acosh),
    OP_acos => (1, acos),
    OPSUMLIST => (-1, sum),
    # OPintDIV = 55
    # OPprecision = 56
    # OPround = 57
    # OPtrunc = 58
    # OPCOUNT = 59
    # OPNUMBEROF = 60
    # OPNUMBEROFs = 61
    # OPATLEAST = 62
    # OPATMOST = 63
    # OPPLTERM = 64
    # OPIFSYM = 65
    # OPEXACTLY = 66
    # OPNOTATLEAST = 67
    # OPNOTATMOST = 68
    # OPNOTEXACTLY = 69
    # ANDLIST = 70
    # ORLIST = 71
    # OPIMPELSE = 72
    # OP_IFF = 73
    # OPALLDIFF = 74
    # OPSOMESAME = 75
    # OP1POW = 76
    # OP2POW = 77
    # OPCPOW = 78
    # OPFUNCALL = 79
    # OPNUM = 80
    # OPHOL = 81
    # OPVARVAL = 82
    # N_OPS = 83
)

"""
    _NARY_OPCODES

A manually curated list of n-ary opcodes, taken from Table 8 of "Writing .nl
files."
"""
const _NARY_OPCODES = Set([
    MINLIST,
    MAXLIST,
    OPSUMLIST,
    # OPCOUNT,
    # OPNUMBEROF,
    # OPNUMBEROFs,
    # ANDLIST,
    # ORLIST,
    # OPALLDIFF,
])

"""
    _UNARY_SPECIAL_CASES

This dictionary defines a set of unary functions that are special-cased. They
don't exist in the NL file format, but they may be called from Julia, and
they can easily be converted into NL-compatible expressions.

If you have a new unary-function that you want to support, add it here.
"""
const _UNARY_SPECIAL_CASES = Dict(
    :cbrt => (x) -> :($x^(1 / 3)),
    :abs2 => (x) -> :($x^2),
    :inv => (x) -> :(1 / $x),
    :log2 => (x) -> :(log($x) / log(2)),
    :log1p => (x) -> :(log(1 + $x)),
    :exp2 => (x) -> :(2^$x),
    :expm1 => (x) -> :(exp($x) - 1),
    :sec => (x) -> :(1 / cos($x)),
    :csc => (x) -> :(1 / sin($x)),
    :cot => (x) -> :(1 / tan($x)),
    :asec => (x) -> :(acos(1 / $x)),
    :acsc => (x) -> :(asin(1 / $x)),
    :acot => (x) -> :(pi / 2 - atan($x)),
    :sind => (x) -> :(sin(pi / 180 * $x)),
    :cosd => (x) -> :(cos(pi / 180 * $x)),
    :tand => (x) -> :(tan(pi / 180 * $x)),
    :secd => (x) -> :(1 / cos(pi / 180 * $x)),
    :cscd => (x) -> :(1 / sin(pi / 180 * $x)),
    :cotd => (x) -> :(1 / tan(pi / 180 * $x)),
    :asind => (x) -> :(asin($x) * 180 / pi),
    :acosd => (x) -> :(acos($x) * 180 / pi),
    :atand => (x) -> :(atan($x) * 180 / pi),
    :asecd => (x) -> :(acos(1 / $x) * 180 / pi),
    :acscd => (x) -> :(asin(1 / $x) * 180 / pi),
    :acotd => (x) -> :((pi / 2 - atan($x)) * 180 / pi),
    :sech => (x) -> :(1 / cosh($x)),
    :csch => (x) -> :(1 / sinh($x)),
    :coth => (x) -> :(1 / tanh($x)),
    :asech => (x) -> :(acosh(1 / $x)),
    :acsch => (x) -> :(asinh(1 / $x)),
    :acoth => (x) -> :(atanh(1 / $x)),
)
