`timescale 1ns/1ps
// =============================================================================
// fp_mul.v  --  32-bit floating-point multiplier:  y = a * b      (version 2)
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// (See fp_add.v for the float32 bit layout.)
//
// HOW FLOAT MULTIPLICATION WORKS -- scientific notation again:
//     (1.5 x 2^3) * (1.25 x 2^4) = (1.5 * 1.25) x 2^(3+4) = 1.875 x 2^7
//   sign     = sign_a XOR sign_b        (neg * neg = pos)
//   exponent = exp_a + exp_b - 127      (both carry a +127 bias; remove one)
//   mantissa = mant_a * mant_b          (24-bit * 24-bit integer multiply)
// Multiplication is actually simpler than addition: no aligning needed.
//
// WHY THIS USES 2 DSP SLICES
//   A DSP slice is a hard-wired multiplier on the chip. The KR260's DSP48E2
//   multiplies 27 bits by 18 bits. Our 24 x 24 multiply does not fit, so
//   Vivado splits it into two smaller multiplies and adds them:
//       mant_a * mant_b = mant_a * b_low17  +  (mant_a * b_high7) << 17
//   -> 2 DSP slices per float multiplier.
//
// PIPELINE (latency = 1 + MULT_STAGES + 3 = 8 cycles):
//   Stage 1        unpack, specials, add exponents
//   Stages 2-5     24 x 24 multiply inside pipe_mult (MULT_STAGES = 4)
//   Stage 6        normalize: pick the right 24 bits, guard and sticky
//   Stage 7        round
//   Stage 8        check range and pack
//
// WHY MORE STAGES THAN VERSION 1 (4 cycles): the 10/21 report showed the
// multiplier topping out around 300 MHz. Version 2 gives the DSP chain
// enough registers (pipe_mult.v) and splits rounding from packing.
// =============================================================================
module fp_mul (
    input  wire        clk,
    input  wire        rst,
    input  wire        in_valid,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire        out_valid,
    output reg  [31:0] y
);
    localparam MULT_STAGES = 4;    // cycles inside pipe_mult (2 DSP slices)

    // =========================================================================
    // STAGE 1: unpack, specials, sign, exponent
    // =========================================================================
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire a_is_zero = (exp_a == 8'd0);
    wire b_is_zero = (exp_b == 8'd0);
    wire a_is_inf  = (exp_a == 8'hff) && (a[22:0] == 23'd0);
    wire b_is_inf  = (exp_b == 8'hff) && (b[22:0] == 23'd0);
    wire a_is_nan  = (exp_a == 8'hff) && (a[22:0] != 23'd0);
    wire b_is_nan  = (exp_b == 8'hff) && (b[22:0] != 23'd0);
    wire sign      = a[31] ^ b[31];                    // ^ is XOR, like C

    wire special = a_is_nan | b_is_nan | a_is_inf | b_is_inf | a_is_zero | b_is_zero;
    reg  [31:0] special_answer;
    always @(*) begin
        if (a_is_nan | b_is_nan | (a_is_inf & b_is_zero) | (b_is_inf & a_is_zero))
            special_answer = 32'h7fc00000;           // NaN (also: inf * 0)
        else if (a_is_inf | b_is_inf)
            special_answer = {sign, 8'hff, 23'd0};   // inf * x = inf
        else
            special_answer = {sign, 31'd0};          // 0 * x = 0
    end

    reg         s1_special, s1_sign;
    reg  [31:0] s1_special_answer;
    reg  signed [9:0] s1_exp;    // signed + 10 bits so overflow/underflow are visible
    reg  [23:0] s1_mant_a, s1_mant_b;

    always @(posedge clk) begin
        s1_special        <= special;
        s1_special_answer <= special_answer;
        s1_sign           <= sign;
        // exp_a + exp_b - 127. {2'b00, exp_a} pads to 10 bits so the sum can't wrap.
        s1_exp            <= $signed({2'b00, exp_a}) + $signed({2'b00, exp_b}) - 10'sd127;
        s1_mant_a         <= {1'b1, a[22:0]};          // glue the hidden 1 back on
        s1_mant_b         <= {1'b1, b[22:0]};
    end

    // =========================================================================
    // STAGES 2-5: 24 x 24 = 48-bit mantissa product (DSP slices)
    // =========================================================================
    wire [47:0] product;                     // ready MULT_STAGES cycles after s1_*
    pipe_mult #(.WA(24), .WB(24), .STAGES(MULT_STAGES)) mant_mult (
        .clk(clk), .a(s1_mant_a), .b(s1_mant_b), .p(product));

    // Signals that wait while the multiply runs (see delay_line.v)
    wire signed [9:0] exp_d;                 // s1_exp, delayed to line up with 'product'
    delay_line #(.WIDTH(10), .DEPTH(MULT_STAGES)) exp_delay (
        .clk(clk), .rst(1'b0), .d(s1_exp), .q(exp_d));

    wire        late_special, late_sign;     // needed by stage 8 (reads stage-7 registers)
    wire [31:0] late_special_answer;
    delay_line #(.WIDTH(34), .DEPTH(MULT_STAGES + 2)) special_delay (
        .clk(clk), .rst(1'b0),
        .d({s1_special, s1_sign, s1_special_answer}),
        .q({late_special, late_sign, late_special_answer}));

    delay_line #(.WIDTH(1), .DEPTH(MULT_STAGES + 4)) valid_delay (
        .clk(clk), .rst(rst), .d(in_valid), .q(out_valid));

    // =========================================================================
    // STAGE 6: normalize -- product is in [1, 4)
    // =========================================================================
    //   product bit 47 = 1 -> value is 2.xxx or 3.xxx: use bits [47:24], exponent + 1
    //   product bit 47 = 0 -> value is 1.xxx:          use bits [46:23]
    reg  [23:0] s6_mant;
    reg         s6_guard, s6_sticky;
    reg  signed [9:0] s6_exp;

    always @(posedge clk) begin
        if (product[47]) begin
            s6_mant   <= product[47:24];
            s6_guard  <= product[23];
            s6_sticky <= |product[22:0];     // OR of every bit below guard
            s6_exp    <= exp_d + 10'sd1;
        end else begin
            s6_mant   <= product[46:23];
            s6_guard  <= product[22];
            s6_sticky <= |product[21:0];
            s6_exp    <= exp_d;
        end
    end

    // =========================================================================
    // STAGE 7: round to nearest-even (see fp_add.v stage 8)
    // =========================================================================
    wire        round_up     = s6_guard & (s6_sticky | s6_mant[0]);
    wire [24:0] mant_rounded = {1'b0, s6_mant} + round_up;

    reg  signed [9:0] s7_exp;
    reg  [22:0] s7_frac;

    always @(posedge clk) begin
        if (mant_rounded[24]) begin          // rounding carried out: 10.000...
            s7_exp  <= s6_exp + 10'sd1;
            s7_frac <= mant_rounded[23:1];
        end else begin
            s7_exp  <= s6_exp;
            s7_frac <= mant_rounded[22:0];
        end
    end

    // =========================================================================
    // STAGE 8: check range, pack
    // =========================================================================
    always @(posedge clk) begin
        if (late_special)
            y <= late_special_answer;
        else if (s7_exp >= 10'sd255)
            y <= {late_sign, 8'hff, 23'd0};          // too big -> infinity
        else if (s7_exp <= 10'sd0)
            y <= {late_sign, 31'd0};                 // too small -> zero
        else
            y <= {late_sign, s7_exp[7:0], s7_frac};
    end

endmodule
