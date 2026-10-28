`timescale 1ns / 1ps
//==============================================================================
// newton_raphson_reciprocal
//
// Computes  result = 1 / operand  for signed fixed-point numbers (DATA_WIDTH
// bits, FRACTION_BITS after the binary point) with Newton-Raphson iterations
// (newton_raphson_core). Fully pipelined: a new operand every clock cycle.
//
// How it works
//   1. Take the magnitude and remember the sign.
//   2. Count leading zeros and shift left so the top bit is 1: the magnitude
//      becomes d * 2^(something), with 0.5 <= d < 1.
//   3. newton_raphson_core finds y ~= 1/d  (1 <= y <= 2).
//   4. Shift y back by the same amount (the other way) and apply the sign.
//   5. Saturate if the answer doesn't fit in the format.
//   Powers of two skip the approximation: d = 0.5 exactly, so 1/d = 2 exactly.
//
// Pipeline (input_valid -> output_valid), 6 + 2 * ITERATIONS * MULTIPLY_STAGES
// cycles: magnitude (1), leading zeros (1), normalize (1), core
// (1 + 2 * ITERATIONS * MULTIPLY_STAGES), shift back (1), sign and saturate (1).
//
// Accuracy: the core keeps 2 guard bits, and every step rounds down, so the
// result is the exact reciprocal truncated toward zero, or 1 LSB smaller in
// magnitude. Exact answers (1/x for x a power of two) are always exact.
// The testbench checks every 16- and 18-bit input.
//
// Out of range: 1/x doesn't fit when |x| is small (Q2.16: |x| < 0.5,
// Q4.12: |x| < 0.125, Q16.16: |x| <= 2^-15). Then the result saturates to the
// largest positive / most negative value and overflow is set. 1/0 gives the
// largest positive value with overflow set (like shift_subtract_divider).
//
// Settings that reach full accuracy (from the Python model):
//   Q4.12 : SEED_BITS 8 + 1 iteration,  or 4 + 2
//   Q2.16 : SEED_BITS 9 + 1 iteration,  or 4 + 2
//   Q16.16: SEED_BITS 8 + 2 iterations, or 4 + 3
//==============================================================================
module newton_raphson_reciprocal #(
    parameter DATA_WIDTH      = 18,
    parameter FRACTION_BITS   = 16,
    parameter SEED_BITS       = 9,
    parameter ITERATIONS      = 1,
    parameter MULTIPLY_STAGES = 1    // 1 to 3
)(
    input  wire                         clock,
    input  wire                         input_valid,
    input  wire signed [DATA_WIDTH-1:0] operand,
    output reg                          output_valid = 0,
    output reg  signed [DATA_WIDTH-1:0] result,
    output reg                          overflow       // result saturated (or 1/0)
);
    localparam Y_BITS      = DATA_WIDTH + 2;        // core result: 2 guard bits
    localparam SHIFT_WIDTH = $clog2(DATA_WIDTH + 1);
    // y * 2^-Y_BITS = 1/d, and 1/x = (1/d) * 2^(FRACTION_BITS + leading_zeros - DATA_WIDTH),
    // so result = y >> (SHIFT_BACK_BASE - leading_zeros)
    localparam SHIFT_BACK_BASE = DATA_WIDTH + Y_BITS - 2 * FRACTION_BITS;

    localparam [DATA_WIDTH-1:0] LARGEST_POSITIVE = {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam [DATA_WIDTH-1:0] MOST_NEGATIVE    = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    //--------------------------------------------------------------------------
    // 1. Magnitude and sign
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] magnitude_1;
    reg                  sign_1, valid_1 = 0;

    always @(posedge clock) begin
        magnitude_1 <= operand[DATA_WIDTH-1] ? -operand : operand;
        sign_1      <= operand[DATA_WIDTH-1];
        valid_1     <= input_valid;
    end

    //--------------------------------------------------------------------------
    // 2. Leading zeros (DATA_WIDTH when the operand is 0)
    //--------------------------------------------------------------------------
    function [SHIFT_WIDTH-1:0] count_leading_zeros(input [DATA_WIDTH-1:0] value);
        integer i;
        begin
            count_leading_zeros = DATA_WIDTH;
            for (i = 0; i < DATA_WIDTH; i = i + 1)
                if (value[i]) count_leading_zeros = DATA_WIDTH - 1 - i;   // highest 1 wins
        end
    endfunction

    reg [DATA_WIDTH-1:0]  magnitude_2;
    reg [SHIFT_WIDTH-1:0] leading_zeros_2;
    reg                   sign_2, valid_2 = 0;

    always @(posedge clock) begin
        magnitude_2     <= magnitude_1;
        leading_zeros_2 <= count_leading_zeros(magnitude_1);
        sign_2          <= sign_1;
        valid_2         <= valid_1;
    end

    //--------------------------------------------------------------------------
    // 3. Normalize: top bit becomes 1, so d = divisor_3 / 2^DATA_WIDTH is in [0.5, 1)
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0]  divisor_3;
    reg [SHIFT_WIDTH-1:0] leading_zeros_3;
    reg                   sign_3, zero_3, power_of_two_3, valid_3 = 0;

    always @(posedge clock) begin
        divisor_3       <= magnitude_2 << leading_zeros_2;
        leading_zeros_3 <= leading_zeros_2;
        sign_3          <= sign_2;
        zero_3          <= (magnitude_2 == 0);
        power_of_two_3  <= ((magnitude_2 & (magnitude_2 - 1)) == 0);
        valid_3         <= valid_2;
    end

    //--------------------------------------------------------------------------
    // 4. y ~= 1/d; sign, zero flag and shift ride along as the tag
    //--------------------------------------------------------------------------
    wire                   core_valid;
    wire [Y_BITS:0]        core_reciprocal;
    wire                   core_sign, core_zero, core_power_of_two;
    wire [SHIFT_WIDTH-1:0] core_leading_zeros;

    newton_raphson_core #(
        .D_BITS(DATA_WIDTH), .Y_BITS(Y_BITS), .SEED_BITS(SEED_BITS),
        .ITERATIONS(ITERATIONS), .MULTIPLY_STAGES(MULTIPLY_STAGES), .TAG_WIDTH(SHIFT_WIDTH + 3)
    ) core (
        .clock(clock),
        .input_valid(valid_3),
        .divisor(divisor_3),
        .input_tag({sign_3, zero_3, power_of_two_3, leading_zeros_3}),
        .output_valid(core_valid),
        .reciprocal(core_reciprocal),
        .output_tag({core_sign, core_zero, core_power_of_two, core_leading_zeros}));

    //--------------------------------------------------------------------------
    // 5. Shift back; flag results that don't fit
    //--------------------------------------------------------------------------
    reg [Y_BITS+1:0] magnitude_5;
    reg              sign_5, overflow_5, valid_5 = 0;

    wire [Y_BITS+1:0] exact_or_approximate = core_power_of_two ? (2'b10 << Y_BITS)   // 2.0
                                                               : {1'b0, core_reciprocal};
    wire [Y_BITS+1:0] shifted_back = exact_or_approximate >> (SHIFT_BACK_BASE - core_leading_zeros);

    always @(posedge clock) begin
        magnitude_5 <= shifted_back;
        sign_5      <= core_sign;
        // Too big: 1/0, a shift the other way (huge result), or above the
        // largest magnitude (one more is allowed for negative results)
        overflow_5  <= core_zero
                    || (core_leading_zeros > SHIFT_BACK_BASE)
                    || (shifted_back > {1'b0, LARGEST_POSITIVE} + core_sign);
        valid_5     <= core_valid;
    end

    //--------------------------------------------------------------------------
    // 6. Sign and saturation
    //--------------------------------------------------------------------------
    always @(posedge clock) begin
        if (overflow_5)
            result <= sign_5 ? MOST_NEGATIVE : LARGEST_POSITIVE;
        else
            result <= sign_5 ? -magnitude_5[DATA_WIDTH-1:0] : magnitude_5[DATA_WIDTH-1:0];
        overflow     <= overflow_5;
        output_valid <= valid_5;
    end
endmodule
