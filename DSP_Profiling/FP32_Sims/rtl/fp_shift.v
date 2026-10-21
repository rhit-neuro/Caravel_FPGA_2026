`timescale 1ns/1ps
// =============================================================================
// fp_shift.v  --  floating-point "shift":  y = a * 2^k
// =============================================================================
// On an integer, shifting left by k multiplies by 2^k (x << 3 == x * 8).
// On a float, the mantissa does not move at all -- we just add k to the
// exponent field. Same as C's ldexpf(a, k).
//
//   example: 1.5 x 2^3  shifted by k = 2  ->  1.5 x 2^5
//
// This is why shifting is almost free in floating point: one 8-bit add,
// no DSP slices.  Pipeline: 1 stage, latency = 1 cycle.
// =============================================================================
module fp_shift (
    input  wire              clk,
    input  wire              rst,
    input  wire              in_valid,
    input  wire [31:0]       a,
    input  wire signed [8:0] k,        // shift amount, -256..255 (negative = divide)
    output reg               out_valid,
    output reg  [31:0]       y
);
    wire [7:0] exp_a = a[30:23];

    // New exponent = old exponent + k. Use 11 signed bits so we can see if
    // the result went below 1 or above 254 (out of float range).
    wire signed [10:0] exp_new = $signed({3'b000, exp_a}) + k;

    always @(posedge clk) begin
        out_valid <= rst ? 1'b0 : in_valid;
        if (exp_a == 8'd0)
            y <= {a[31], 31'd0};                  // zero stays zero
        else if (exp_a == 8'hff)
            y <= a;                               // inf / NaN stay as they are
        else if (exp_new >= 11'sd255)
            y <= {a[31], 8'hff, 23'd0};           // too big -> infinity
        else if (exp_new <= 11'sd0)
            y <= {a[31], 31'd0};                  // too small -> zero
        else
            y <= {a[31], exp_new[7:0], a[22:0]};  // same sign, same fraction, new exponent
    end
endmodule
