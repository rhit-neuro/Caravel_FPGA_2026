`timescale 1ns / 1ps
//==============================================================================
// float_newton_raphson_reciprocal
//
// result = 1 / operand  for IEEE half (DATA_WIDTH 16) or single (32) floats,
// using the same Newton-Raphson core as the fixed-point reciprocal
// (../../rtl/newton_raphson_core.v). Fully pipelined: a new operand every cycle.
//
// How it works
//   x = 1.f * 2^(E - bias)  ->  1/x = (1 / 1.f) * 2^(bias - E).
//   With d = 1.f / 2 (0.5 <= d < 1, no shifting needed: floats are already
//   normalized), the core gives y ~= 1/d (1 < y < 2), and
//   1/x = y * 2^(bias - 1 - E): y is the new mantissa, the exponent is
//   2*bias - 1 - E. y is rounded to nearest (ties away from zero), which can
//   carry into the exponent.
//   Powers of two (f = 0) are exact: mantissa 0, exponent 2*bias - E.
//
// Accuracy: the core keeps 4 guard bits and is within 0.2 ulp before
// rounding, so every result is within 1 ulp of the exact 1/x and almost
// always the correctly rounded one.
//
// Special values: 1/(+-0) = +-infinity, 1/(+-infinity) = +-0, NaN -> NaN.
// Subnormals are treated as zero (in and out), like AMD's Floating-Point IP.
//
// Latency (input_valid -> output_valid): 2 + 2 * ITERATIONS * MULTIPLY_STAGES
//   (core: 1 seed + 2 multiply ops per iteration; 1 to round and pack)
//
// Settings that reach full accuracy (from the Python model):
//   half  : SEED_BITS 7 + 1 iteration,  or 3 + 2
//   single: SEED_BITS 7 + 2 iterations, or 4 + 3
//==============================================================================
module float_newton_raphson_reciprocal #(
    parameter DATA_WIDTH      = 32,   // 16 = half, 32 = single
    parameter SEED_BITS       = 7,
    parameter ITERATIONS      = 2,
    parameter MULTIPLY_STAGES = 1     // 1 to 3
)(
    input  wire                  clock,
    input  wire                  input_valid,
    input  wire [DATA_WIDTH-1:0] operand,
    output reg                   output_valid = 0,
    output reg  [DATA_WIDTH-1:0] result
);
    localparam EXPONENT_BITS = (DATA_WIDTH == 16) ? 5 : 8;
    localparam MANTISSA_BITS = (DATA_WIDTH == 16) ? 10 : 23;
    localparam BIAS          = (1 << (EXPONENT_BITS - 1)) - 1;
    localparam D_BITS        = MANTISSA_BITS + 1;
    localparam Y_BITS        = MANTISSA_BITS + 4;   // 4 guard bits for rounding

    localparam [EXPONENT_BITS-1:0] EXPONENT_ALL_ONES = {EXPONENT_BITS{1'b1}};

    // Input classes (carried through the core in the tag)
    localparam [1:0] CLASS_NORMAL   = 2'd0,
                     CLASS_ZERO     = 2'd1,   // zero or subnormal -> infinity
                     CLASS_INFINITY = 2'd2,   // -> zero
                     CLASS_NAN      = 2'd3;   // -> NaN

    //--------------------------------------------------------------------------
    // Unpack (wiring and a few comparisons; no register needed)
    //--------------------------------------------------------------------------
    wire                     sign     = operand[DATA_WIDTH-1];
    wire [EXPONENT_BITS-1:0] exponent = operand[DATA_WIDTH-2 -: EXPONENT_BITS];
    wire [MANTISSA_BITS-1:0] fraction = operand[MANTISSA_BITS-1:0];

    wire [1:0] input_class = (exponent == 0)                 ? CLASS_ZERO :
                             (exponent != EXPONENT_ALL_ONES) ? CLASS_NORMAL :
                             (fraction == 0)                 ? CLASS_INFINITY : CLASS_NAN;
    wire       power_of_two = (fraction == 0);

    //--------------------------------------------------------------------------
    // y ~= 1 / (1.f / 2)
    //--------------------------------------------------------------------------
    wire                     core_valid;
    wire [Y_BITS:0]          core_reciprocal;
    wire                     core_sign, core_power_of_two;
    wire [1:0]               core_class;
    wire [EXPONENT_BITS-1:0] core_exponent;

    newton_raphson_core #(
        .D_BITS(D_BITS), .Y_BITS(Y_BITS), .SEED_BITS(SEED_BITS),
        .ITERATIONS(ITERATIONS), .MULTIPLY_STAGES(MULTIPLY_STAGES), .TAG_WIDTH(EXPONENT_BITS + 4)
    ) core (
        .clock(clock),
        .input_valid(input_valid),
        .divisor({1'b1, fraction}),
        .input_tag({sign, power_of_two, input_class, exponent}),
        .output_valid(core_valid),
        .reciprocal(core_reciprocal),
        .output_tag({core_sign, core_power_of_two, core_class, core_exponent}));

    //--------------------------------------------------------------------------
    // Round, set the exponent, pack
    //--------------------------------------------------------------------------
    // Mantissa with its leading 1, rounded to nearest: may become 2.0
    wire [MANTISSA_BITS+1:0] rounded_mantissa =
        core_reciprocal[Y_BITS -: MANTISSA_BITS + 1] + core_reciprocal[Y_BITS - MANTISSA_BITS - 1];
    wire                     round_carry = rounded_mantissa[MANTISSA_BITS + 1];

    // New exponent field, computed wide enough to see 0 or below (-> flush to zero)
    wire signed [EXPONENT_BITS+1:0] result_exponent =
        core_power_of_two ? 2 * BIAS - core_exponent
                          : 2 * BIAS - 1 - core_exponent + round_carry;

    wire [MANTISSA_BITS-1:0] result_fraction =
        (core_power_of_two || round_carry) ? {MANTISSA_BITS{1'b0}} : rounded_mantissa[MANTISSA_BITS-1:0];

    always @(posedge clock) begin
        case (core_class)
            CLASS_ZERO:     result <= {core_sign, EXPONENT_ALL_ONES, {MANTISSA_BITS{1'b0}}};          // infinity
            CLASS_INFINITY: result <= {core_sign, {(DATA_WIDTH-1){1'b0}}};                           // zero
            CLASS_NAN:      result <= {1'b0, EXPONENT_ALL_ONES, 1'b1, {(MANTISSA_BITS-1){1'b0}}};    // quiet NaN
            default:
                if (result_exponent <= 0)
                    result <= {core_sign, {(DATA_WIDTH-1){1'b0}}};                                   // too small: zero
                else
                    result <= {core_sign, result_exponent[EXPONENT_BITS-1:0], result_fraction};
        endcase
        output_valid <= core_valid;
    end
endmodule
