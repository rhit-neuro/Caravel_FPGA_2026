`timescale 1ns/1ps
// =============================================================================
// fp_add.v  --  32-bit floating-point adder:  y = a + b          (version 2)
// =============================================================================
// FLOAT32 REFRESHER (IEEE-754 single precision, same as C's 'float')
//
//     bit 31    bits 30..23      bits 22..0
//   +------+----------------+----------------------+
//   | sign |  exponent (8)  |    fraction (23)     |
//   +------+----------------+----------------------+
//   value = (-1)^sign * 1.fraction * 2^(exponent - 127)
//
//   * The "1." in front of the fraction is NOT stored (the "hidden bit").
//     When we unpack, we glue it back on: mantissa = {1, fraction} = 24 bits.
//   * exponent = 0   -> we treat the number as zero (tiny "subnormal" numbers
//                       are flushed to zero to keep the hardware simple)
//   * exponent = 255 -> infinity (fraction = 0) or NaN (fraction != 0)
//
// HOW FLOAT ADDITION WORKS -- same as adding in scientific notation:
//     1.20 x 10^5  +  3.40 x 10^3
//   = 1.20 x 10^5  +  0.034 x 10^5    <- line up the exponents first
//   = 1.234 x 10^5                    <- then add the digits
//
// PIPELINE: 9 stages, latency = 9 cycles, a new (a, b) every cycle.
//   Stage 1  unpack, special values, compare magnitudes
//   Stage 2  swap so 'big' has the larger magnitude
//   Stage 3  ALIGN: shift small's mantissa right by the exponent difference
//   Stage 4  collect the bits that fell off into the sticky bit
//   Stage 5  ADD the mantissas (or SUBTRACT if the signs differ)
//   Stage 6  count leading zeros of the result
//   Stage 7  NORMALIZE: shift so the result looks like 1.xxxx again
//   Stage 8  ROUND to 24 bits
//   Stage 9  check overflow/underflow and pack back into 32 bits
//
// WHY 9 STAGES (version 1 had 5): the 10/21 timing report showed the adder
// topping out around 300-360 MHz. Each clock cycle can only fit so much
// logic, so version 2 gives every slow step (compare, shift, add, count,
// shift, round) its own cycle. More cycles per answer, but a faster clock.
//
// ROUNDING: round to nearest, ties to even (the C/IEEE default). To round
// correctly we keep 3 extra bits below the 24-bit mantissa while working:
//   guard  = the first bit below the mantissa
//   round  = the second bit below
//   sticky = 1 if ANY bit further below was 1 (all the "lost" bits ORed)
// =============================================================================
module fp_add (
    input  wire        clk,        // clock
    input  wire        rst,        // reset (clears the valid flags)
    input  wire        in_valid,   // 1 = a and b are a new problem this cycle
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire        out_valid,  // 1 = y is an answer this cycle
    output reg  [31:0] y           // a + b
);

    // =========================================================================
    // PASSENGER SIGNALS: these are decided early but only used in stage 9,
    // so they ride along in delay lines (see delay_line.v) instead of being
    // copied stage by stage.
    // =========================================================================
    wire        special;              // decided in stage 1 (input is NaN/inf/0+0)
    reg  [31:0] special_answer;
    wire        late_special;         // the same, 8 cycles later (ready for stage 9)
    wire [31:0] late_special_answer;
    reg         s2_sign;              // result sign, decided in stage 2
    wire        late_sign;            // the same, 6 cycles later

    // valid flag: in_valid delayed by all 9 stages
    delay_line #(.WIDTH(1), .DEPTH(9)) valid_delay (
        .clk(clk), .rst(rst), .d(in_valid), .q(out_valid));

    // =========================================================================
    // STAGE 1: unpack, detect special values, compare magnitudes
    // =========================================================================
    // These are wires: pure combinational logic, computed instantly from a, b.
    wire [7:0] exp_a = a[30:23];             // exponent field of a
    wire [7:0] exp_b = b[30:23];             // exponent field of b

    wire a_is_zero = (exp_a == 8'd0);        // exponent 0 -> treat as zero
    wire b_is_zero = (exp_b == 8'd0);
    wire a_is_inf  = (exp_a == 8'hff) && (a[22:0] == 23'd0);
    wire b_is_inf  = (exp_b == 8'hff) && (b[22:0] == 23'd0);
    wire a_is_nan  = (exp_a == 8'hff) && (a[22:0] != 23'd0);
    wire b_is_nan  = (exp_b == 8'hff) && (b[22:0] != 23'd0);

    // Which one is bigger in magnitude? A neat float trick: for positive
    // floats, comparing the 31 bits {exponent, fraction} as an unsigned
    // integer gives the same answer as comparing the float values.
    wire [30:0] mag_a = a_is_zero ? 31'd0 : a[30:0];
    wire [30:0] mag_b = b_is_zero ? 31'd0 : b[30:0];

    // Special cases skip the normal math. Their answer is decided here.
    assign special = a_is_nan | b_is_nan | a_is_inf | b_is_inf | (a_is_zero & b_is_zero);
    //combinational logic, asynchronous and triggers if any signal inside changes
    always @(*) begin
        if (a_is_nan | b_is_nan | (a_is_inf & b_is_inf & (a[31] != b[31])))
            special_answer = 32'h7fc00000;            // NaN (also: inf - inf)
        else if (a_is_inf)
            special_answer = a;                       // inf + anything = inf
        else if (b_is_inf)
            special_answer = b;
        else
            special_answer = {a[31] & b[31], 31'd0};  // 0 + 0 = 0 (-0 only if both -0)
    end

    // 'special' is computed straight from the inputs (not yet registered),
    // and stage 9 reads stage-8 registers, so it needs 8 cycles of delay.
    delay_line #(.WIDTH(33), .DEPTH(8)) special_delay (
        .clk(clk), .rst(1'b0),
        .d({special, special_answer}), .q({late_special, late_special_answer}));

    reg         s1_a_bigger;
    reg         s1_sign_a, s1_sign_b;
    reg  [7:0]  s1_exp_a, s1_exp_b;
    reg  [7:0]  s1_diff_ab, s1_diff_ba;      // exp_a - exp_b and exp_b - exp_a
    reg  [23:0] s1_mant_a, s1_mant_b;        // mantissas with the hidden 1 glued on

    always @(posedge clk) begin
        s1_a_bigger <= (mag_a >= mag_b);
        s1_sign_a   <= a[31];
        s1_sign_b   <= b[31];
        s1_exp_a    <= exp_a;
        s1_exp_b    <= exp_b;
        s1_diff_ab  <= exp_a - exp_b;        // compute both differences now,
        s1_diff_ba  <= exp_b - exp_a;        // pick the right one in stage 2
        s1_mant_a   <= a_is_zero ? 24'd0 : {1'b1, a[22:0]};
        s1_mant_b   <= b_is_zero ? 24'd0 : {1'b1, b[22:0]};
    end

    // =========================================================================
    // STAGE 2: swap so 'big' is the operand with the larger magnitude
    // =========================================================================
    reg         s2_subtract;            // 1 if signs differ -> subtract
    reg  [7:0]  s2_exp, s2_diff;
    reg  [23:0] s2_mant_big, s2_mant_small;

    always @(posedge clk) begin
        s2_subtract <= (s1_sign_a != s1_sign_b);
        if (s1_a_bigger) begin              // big = a, small = b
            s2_sign       <= s1_sign_a;
            s2_exp        <= s1_exp_a;
            s2_diff       <= s1_diff_ab;
            s2_mant_big   <= s1_mant_a;
            s2_mant_small <= s1_mant_b;
        end else begin                      // big = b, small = a
            s2_sign       <= s1_sign_b;
            s2_exp        <= s1_exp_b;
            s2_diff       <= s1_diff_ba;
            s2_mant_big   <= s1_mant_b;
            s2_mant_small <= s1_mant_a;
        end
    end

    delay_line #(.WIDTH(1), .DEPTH(6)) sign_delay (
        .clk(clk), .rst(1'b0), .d(s2_sign), .q(late_sign));

    // =========================================================================
    // STAGE 3: ALIGN -- shift the small mantissa right by the exponent difference
    // =========================================================================
    // We place the small mantissa at the top of a 51-bit window (24 mantissa
    // bits + 27 zeros) and shift the whole window right. Bits that would
    // "fall off" a 24-bit number land in the lower part of the window
    // instead of disappearing, so stage 4 can still see them.
    // A shift of 50+ pushes everything out anyway, so cap it at 50.
    wire [7:0] shift_amt = (s2_diff > 8'd50) ? 8'd50 : s2_diff;

    reg         s3_subtract;
    reg  [7:0]  s3_exp;
    reg  [23:0] s3_mant_big;
    reg  [50:0] s3_window;

    always @(posedge clk) begin
        s3_subtract <= s2_subtract;
        s3_exp      <= s2_exp;
        s3_mant_big <= s2_mant_big;
        s3_window   <= {s2_mant_small, 27'd0} >> shift_amt;
    end

    // =========================================================================
    // STAGE 4: build the 27-bit working numbers
    // =========================================================================
    // Working format (27 bits):  [26:3] = 24-bit mantissa
    //                            [2]    = guard
    //                            [1]    = round
    //                            [0]    = sticky
    //   window[50:25] = mantissa + guard + round (26 bits we keep)
    //   window[24:0]  = bits that fell off -> OR them all into sticky
    reg         s4_subtract;
    reg  [7:0]  s4_exp;
    reg  [26:0] s4_big, s4_small;

    always @(posedge clk) begin
        s4_subtract <= s3_subtract;
        s4_exp      <= s3_exp;
        s4_big      <= {s3_mant_big, 3'b000};                 // big needs no shift
        s4_small    <= {s3_window[50:25], |s3_window[24:0]};
    end

    // =========================================================================
    // STAGE 5: ADD or SUBTRACT the aligned mantissas
    // =========================================================================
    // The sum gets 1 extra top bit (28 bits) because 1.x + 1.x can reach 3.x.
    // Subtracting never goes negative because we made sure big >= small.
    reg  [7:0]  s5_exp;
    reg  [27:0] s5_sum;

    always @(posedge clk) begin
        s5_exp <= s4_exp;
        if (s4_subtract)
            s5_sum <= {1'b0, s4_big} - {1'b0, s4_small};
        else
            s5_sum <= {1'b0, s4_big} + {1'b0, s4_small};
    end

    // =========================================================================
    // STAGE 6: count leading zeros (how far stage 7 must shift left)
    // =========================================================================
    // A Verilog 'function' works like a C function, but it becomes a block of
    // logic gates (a "priority encoder"), not a loop that runs over time.
    function [4:0] count_leading_zeros;
        input [26:0] v;
        integer k;
        reg found;
        begin
            count_leading_zeros = 5'd27;          // if v is all zeros
            found = 1'b0;
            for (k = 26; k >= 0; k = k - 1)       // scan from the top bit down
                if (!found && v[k]) begin
                    count_leading_zeros = 26 - k; // zeros above the first 1
                    found = 1'b1;
                end
        end
    endfunction

    reg  [7:0]  s6_exp;
    reg  [27:0] s6_sum;
    reg  [4:0]  s6_lz;
    reg         s6_is_zero;

    always @(posedge clk) begin
        s6_exp     <= s5_exp;
        s6_sum     <= s5_sum;
        s6_lz      <= count_leading_zeros(s5_sum[26:0]);
        s6_is_zero <= (s5_sum == 28'd0);                  // e.g. x - x
    end

    // =========================================================================
    // STAGE 7: NORMALIZE -- make the result look like 1.xxxx again
    // =========================================================================
    //  (a) Addition overflowed into bit 27 (e.g. 1.5 + 1.5 = 3.0 = 11.0b):
    //      shift right by 1 and add 1 to the exponent.
    //  (b) Otherwise shift left by the leading-zero count (this undoes
    //      cancellation, e.g. 1.001 - 1.000 = 0.001) and subtract that
    //      count from the exponent.
    reg  signed [9:0] s7_exp;    // signed + wider, so going below 0 or above 255 is visible
    reg  [26:0] s7_norm;         // normalized: bit 26 is the leading 1
    reg         s7_is_zero;

    always @(posedge clk) begin
        s7_is_zero <= s6_is_zero;
        if (s6_sum[27]) begin
            // case (a): shift right 1; the bit that falls off joins sticky
            s7_norm <= {s6_sum[27:2], s6_sum[1] | s6_sum[0]};
            s7_exp  <= $signed({2'b00, s6_exp}) + 10'sd1;
        end else begin
            // case (b): shift left by the leading-zero count
            s7_norm <= s6_sum[26:0] << s6_lz;
            s7_exp  <= $signed({2'b00, s6_exp}) - $signed({5'd0, s6_lz});
        end
    end

    // =========================================================================
    // STAGE 8: ROUND to nearest-even
    // =========================================================================
    wire [23:0] mant   = s7_norm[26:3];   // the 24 bits we keep
    wire        guard  = s7_norm[2];
    wire        round  = s7_norm[1];
    wire        sticky = s7_norm[0];

    // Round up if the dropped part is more than half (guard=1 and something
    // below it is 1), or exactly half and our mantissa is odd (ties-to-even).
    wire        round_up     = guard & (round | sticky | mant[0]);
    // Rounding up can carry all the way out (1.111..1 + 1 = 10.000..0);
    // if so, shift right one and bump the exponent.
    wire [24:0] mant_rounded = {1'b0, mant} + round_up;

    reg  signed [9:0] s8_exp;
    reg  [22:0] s8_frac;         // the 23 stored fraction bits (hidden 1 dropped)
    reg         s8_is_zero;

    always @(posedge clk) begin
        s8_is_zero <= s7_is_zero;
        if (mant_rounded[24]) begin
            s8_exp  <= s7_exp + 10'sd1;
            s8_frac <= mant_rounded[23:1];
        end else begin
            s8_exp  <= s7_exp;
            s8_frac <= mant_rounded[22:0];
        end
    end

    // =========================================================================
    // STAGE 9: check range, pack into 32 bits
    // =========================================================================
    always @(posedge clk) begin
        if (late_special)
            y <= late_special_answer;               // NaN / inf / 0+0 from stage 1
        else if (s8_is_zero)
            y <= 32'd0;                             // exact cancellation = +0
        else if (s8_exp >= 10'sd255)
            y <= {late_sign, 8'hff, 23'd0};         // too big -> infinity
        else if (s8_exp <= 10'sd0)
            y <= {late_sign, 31'd0};                // too small -> zero
        else
            y <= {late_sign, s8_exp[7:0], s8_frac}; // normal answer
    end

endmodule
