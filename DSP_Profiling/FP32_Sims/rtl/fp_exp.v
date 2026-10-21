`timescale 1ns/1ps
// =============================================================================
// fp_exp.v  --  32-bit floating-point exponential:  y = e^a        (version 2)
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// THE MATH TRICK (shift + table + small polynomial)
//   Computers are good at powers of 2, so rewrite e^x as a power of 2:
//
//       e^x = 2^(x * log2(e))                      log2(e) = 1.442695...
//
//   Call z = x * log2(e) and split it into a whole part n and a fraction f:
//       z = n + f,   n = floor(z) (an integer),   0 <= f < 1
//       e^x = 2^n * 2^f
//
//   * 2^n is just a SHIFT: in a float it means "add n to the exponent"
//     (exactly what fp_shift.v does). Free.
//   * 2^f is a number between 1 and 2 -> that becomes our mantissa.
//     Split f again: f = i/128 + r, where i = the top 7 bits of f (0..127)
//     and r = the leftover (r < 1/128):
//         2^f = 2^(i/128) * 2^r
//     - 2^(i/128) comes from a 128-entry lookup table (fp_exp2_rom.v)
//     - 2^r for tiny r is very close to a short polynomial (Taylor series):
//         2^r = e^(r*ln2) ~= 1 + t + t^2/2     where t = r * ln(2)
//       (the error is under 3e-8, below float32's own precision)
//
//   Example: x = 1.0  ->  z = 1.442695  ->  n = 1, f = 0.442695
//            i = floor(0.442695*128) = 56,  r = 0.442695 - 56/128 = 0.005195
//            2^(56/128) = 1.354256 (table),  2^r = 1.003607 (polynomial)
//            mantissa   = 1.354256 * 1.003607 = 1.359141
//            e^1 = 2^1 * 1.359141 = 2.718282   (correct)
//
// FIXED POINT
//   Inside this module we do the math with plain integers in "fixed point",
//   like storing money as whole cents: the integer 150 means 1.50 dollars.
//   Here "units of 2^-30" means the integer V stands for V / 2^30.
//       1.0  = 1073741824 (= 2^30)        0.5 = 536870912
//   Integer math is much cheaper in hardware than float math, and the
//   numbers here stay in known ranges, so fixed point is safe.
//
// RANGE LIMITS (same as C's expf):
//   x >  88.72  -> result is too big for a float  -> +infinity
//   x < -87.33  -> result is too small            -> 0
//   x = NaN     -> NaN
//
// WHAT CHANGED FROM VERSION 1 (10 cycles, ~250 MHz)
//   The 10/21 report's worst path ran from one DSP multiply straight into
//   the next (t = r*ln2 feeding t*t). Version 2 puts every multiply in a
//   pipe_mult (pipe_mult.v) with enough registers for its DSP chain, does
//   the multiply by log2(e) on the unsigned size and applies the sign after
//   (simpler DSP chain), and splits float->fixed into two stages.
//
// PIPELINE TIMELINE (the "@ cycle" numbers say when each value is ready)
//   @1   stage 1  unpack; work out the shift amount for float -> fixed
//   @2   stage 2  shift: |x| as a fixed-point integer
//   @7   M1       |x| * log2(e)                (pipe_mult, 5 stages, ~4 DSPs)
//   @8   stage 3  apply the sign -> z; split z into n, i, r (just wires)
//   @12  M2       t = r * ln2                  (pipe_mult, 4 stages)
//   @16  M3       t * t                        (pipe_mult, 4 stages)
//   @17  stage 4  poly = 1 + t + t^2/2
//   @22  M4       mantissa = table[i] * poly   (pipe_mult, 5 stages, ~4 DSPs)
//   @23  stage 5  round, exponent = n + 127
//   @24  stage 6  check range, pack           -> latency 24 cycles
//   Values that are made early but used late (sign, n, table[i], t, the
//   special-case answer, valid) ride along in delay lines (delay_line.v).
// =============================================================================
module fp_exp (
    input  wire        clk,
    input  wire        rst,
    input  wire        in_valid,
    input  wire [31:0] a,
    output wire        out_valid,
    output reg  [31:0] y
);

    // Constants, stored as integers in fixed point
    localparam [31:0] LOG2E = 32'd3098164009;   // log2(e) * 2^31 = 1.442695 * 2^31
    localparam [31:0] LN2   = 32'd2977044472;   // ln(2)   * 2^32 = 0.693147 * 2^32
    localparam [30:0] ONE   = 31'd1073741824;   // 1.0     * 2^30

    // Multiplier depths and the timeline built from them. If you change a
    // depth, every delay line below adjusts automatically.
    localparam M1 = 5, M2 = 4, M3 = 4, M4 = 5;
    localparam T_PROD1 = 2 + M1;          // |x|*log2e ready         (7)
    localparam T_Z     = T_PROD1 + 1;     // z, n, i, r ready        (8)
    localparam T_T     = T_Z + M2;        // t ready                 (12)
    localparam T_TSQ   = T_T + M3;        // t^2 ready               (16)
    localparam T_POLY  = T_TSQ + 1;       // poly ready              (17)
    localparam T_MANT  = T_POLY + M4;     // table*poly ready        (22)
    localparam T_ROUND = T_MANT + 1;      // rounded result ready    (23)
    localparam T_OUT   = T_ROUND + 1;     // y ready = latency       (24)

    // =========================================================================
    // STAGE 1 (@1): unpack, specials, plan the float -> fixed-point shift
    // =========================================================================
    wire [7:0]  exp_a   = a[30:23];
    wire        is_nan  = (exp_a == 8'hff) && (a[22:0] != 23'd0);
    wire        is_zero = (exp_a == 8'd0);         // e^0 = 1 (handled by the normal path)
    wire        too_big = (exp_a >= 8'd134);       // |x| >= 128 (this includes infinity)

    // Float -> fixed point (units of 2^-30).
    // The float's value is mant * 2^(exp_a - 127 - 23). To express it in
    // units of 2^-30 we shift mant left by (exp_a - 127 - 23 + 30) = (exp_a - 120).
    // If that number is negative, shift right instead.
    reg         s1_sign, s1_zero, s1_left;
    reg  [23:0] s1_mant;
    reg  [7:0]  s1_amount;                        // how far to shift
    reg         s1_special;
    reg  [31:0] s1_special_answer;

    always @(posedge clk) begin
        s1_sign    <= a[31];
        s1_zero    <= is_zero;
        s1_mant    <= {1'b1, a[22:0]};            // 1.fraction as a 24-bit integer
        s1_left    <= (exp_a >= 8'd120);          // shift left or right?
        s1_amount  <= (exp_a >= 8'd120) ? (exp_a - 8'd120) : (8'd120 - exp_a);
        s1_special <= is_nan | (too_big & ~is_zero);
        // NaN -> NaN;  huge positive -> +inf;  huge negative -> 0
        s1_special_answer <= is_nan ? 32'h7fc00000 : (a[31] ? 32'd0 : 32'h7f800000);
    end

    // =========================================================================
    // STAGE 2 (@2): do the shift -> |x| as a fixed-point integer (37 bits, |x| < 128)
    // =========================================================================
    reg  [36:0] s2_xmag;
    reg         s2_sign;

    always @(posedge clk) begin
        s2_sign <= s1_sign;
        if (s1_zero)
            s2_xmag <= 37'd0;
        else if (s1_left)
            s2_xmag <= {13'd0, s1_mant} << s1_amount;   // amount is 0..13 here (|x| < 128)
        else
            s2_xmag <= {13'd0, s1_mant} >> s1_amount;   // tiny x: bits fall off, fine
    end

    // =========================================================================
    // M1 (@7): |x| * log2(e)        units: 2^-30 * 2^-31 = 2^-61
    // =========================================================================
    wire [68:0] prod1;
    pipe_mult #(.WA(37), .WB(32), .STAGES(M1)) mult_log2e (
        .clk(clk), .a(s2_xmag), .b(LOG2E), .p(prod1));

    wire sign_d;                                    // sign, waiting for prod1
    delay_line #(.WIDTH(1), .DEPTH(M1)) sign_delay (
        .clk(clk), .rst(1'b0), .d(s2_sign), .q(sign_d));

    // =========================================================================
    // STAGE 3 (@8): apply the sign -> z = x * log2(e), then split z
    // =========================================================================
    reg  signed [70:0] s3_z;                        // units of 2^-61

    always @(posedge clk) begin
        if (sign_d)
            s3_z <= -$signed({2'b00, prod1});       // two's-complement negate, like C
        else
            s3_z <=  $signed({2'b00, prod1});
    end

    // Shift right by 31 to go from units 2^-61 to units 2^-30. Now the low
    // 30 bits are the fraction and everything above is the whole part.
    // '>>>' keeps the sign, so for negative z the whole part is floor(z):
    //   z = -0.25 -> n = -1, f = 0.75   (because -1 + 0.75 = -0.25)
    wire signed [39:0] z30 = s3_z >>> 31;           // z in units of 2^-30 (just wiring)
    wire signed [9:0]  n   = z30[39:30];            // whole part: -185..184
    wire        [6:0]  i   = z30[29:23];            // top 7 fraction bits -> table index
    wire        [22:0] r   = z30[22:0];             // the rest (< 1/128), units of 2^-30

    // =========================================================================
    // Table lookup 2^(i/128) (@8), then wait until the poly is ready (@17)
    // =========================================================================
    wire [30:0] table_now, table_d;                 // 2^(i/128) in units of 2^-30
    fp_exp2_rom rom (.idx(i), .val(table_now));     // instance of the lookup table
    delay_line #(.WIDTH(31), .DEPTH(T_POLY - T_Z)) table_delay (
        .clk(clk), .rst(1'b0), .d(table_now), .q(table_d));

    wire signed [9:0] n_d;                          // n, waiting for the mantissa (@22)
    delay_line #(.WIDTH(10), .DEPTH(T_MANT - T_Z)) n_delay (
        .clk(clk), .rst(1'b0), .d(n), .q(n_d));

    // =========================================================================
    // M2 (@12): t = r * ln(2)
    // =========================================================================
    // r (units 2^-30) * LN2 (units 2^-32) = units 2^-62.
    // Keep bits [54:32] to get back to units of 2^-30.
    wire [54:0] r_times_ln2;
    pipe_mult #(.WA(23), .WB(32), .STAGES(M2)) mult_ln2 (
        .clk(clk), .a(r), .b(LN2), .p(r_times_ln2));
    wire [22:0] t = r_times_ln2[54:32];

    // =========================================================================
    // M3 (@16): t^2   (units of 2^-60)
    // =========================================================================
    wire [45:0] t_squared;
    pipe_mult #(.WA(23), .WB(23), .STAGES(M3)) mult_tsq (
        .clk(clk), .a(t), .b(t), .p(t_squared));

    wire [22:0] t_d;                                // t, waiting for t^2
    delay_line #(.WIDTH(23), .DEPTH(M3)) t_delay (
        .clk(clk), .rst(1'b0), .d(t), .q(t_d));

    // =========================================================================
    // STAGE 4 (@17): poly = 1 + t + t^2/2   (all in units of 2^-30)
    // =========================================================================
    // t^2 is in units 2^-60. Shifting right by 30 gives units 2^-30, and one
    // more bit (31 total) divides by 2. So t^2/2 = t_squared >> 31.
    reg [30:0] s4_poly;

    always @(posedge clk)
        s4_poly <= ONE + {8'd0, t_d} + {16'd0, t_squared[45:31]};

    // =========================================================================
    // M4 (@22): mantissa = table * poly  (= 2^f, a number in [1, 2))
    // =========================================================================
    // units: 2^-30 * 2^-30 = 2^-60, so 1.0 = bit 60.
    wire [61:0] m;
    pipe_mult #(.WA(31), .WB(31), .STAGES(M4)) mult_mant (
        .clk(clk), .a(table_d), .b(s4_poly), .p(m));

    // =========================================================================
    // STAGE 5 (@23): round, exponent = n + 127
    // =========================================================================
    // Normally bit 60 is the leading 1 (value in [1,2)). Tiny rounding error
    // could push it just to 2.0 (bit 61) -- handle that too.
    wire        top_bit  = m[61];
    wire [23:0] mant     = top_bit ? m[61:38] : m[60:37];  // 24 bits we keep
    wire        round_up = top_bit ? m[37]    : m[36];     // first dropped bit
    wire [24:0] mant_rounded = {1'b0, mant} + round_up;

    reg  signed [10:0] s5_exp;
    reg  [22:0] s5_frac;

    always @(posedge clk) begin
        // float exponent field = n + 127 (+1 for each carry)
        s5_exp  <= $signed({n_d[9], n_d}) + 11'sd127
                   + (top_bit          ? 11'sd1 : 11'sd0)
                   + (mant_rounded[24] ? 11'sd1 : 11'sd0);
        s5_frac <= mant_rounded[24] ? mant_rounded[23:1] : mant_rounded[22:0];
    end

    // =========================================================================
    // STAGE 6 (@24): check range, pack
    // =========================================================================
    wire        late_special;                       // from stage 1, ready @23
    wire [31:0] late_special_answer;
    delay_line #(.WIDTH(33), .DEPTH(T_ROUND - 1)) special_delay (
        .clk(clk), .rst(1'b0),
        .d({s1_special, s1_special_answer}), .q({late_special, late_special_answer}));

    delay_line #(.WIDTH(1), .DEPTH(T_OUT)) valid_delay (
        .clk(clk), .rst(rst), .d(in_valid), .q(out_valid));

    always @(posedge clk) begin
        if (late_special)
            y <= late_special_answer;
        else if (s5_exp >= 11'sd255)
            y <= 32'h7f800000;                       // too big -> +infinity
        else if (s5_exp <= 11'sd0)
            y <= 32'd0;                              // too small -> 0
        else
            y <= {1'b0, s5_exp[7:0], s5_frac};       // e^x is always positive
    end

endmodule
