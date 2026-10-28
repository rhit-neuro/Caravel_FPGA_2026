`timescale 1ns / 1ps
//==============================================================================
// nr_multiply_add
//
// sum = c + a * b   (or c - a * b when SUBTRACT = 1), signed, in one DSP48E2
// when the widths fit (otherwise Vivado spreads it over a few DSPs).
// Used by newton_raphson_core for both steps of a Newton-Raphson iteration.
//
// result = sum[RESULT_SHIFT +: RESULT_WIDTH]   (wiring only: drops low bits,
// rounding down, and keeps only the bits the caller needs)
//
// STAGES = clock cycles from inputs to result, same scheme as
// dsp_fixed_point_multiplier:
//   1 : output register                                   (PREG)
//   2 : input registers + output register                 (AREG/BREG/CREG + PREG)
//   3 : input + multiplier + output registers             (AREG/BREG/CREG + MREG + PREG)
// (A 4th stage, a second multiplier register, was tried for the 32-bit
// version: Vivado kept it in fabric and the clock didn't improve.)
//==============================================================================
(* use_dsp = "yes" *)
module nr_multiply_add #(
    parameter A_WIDTH      = 18,
    parameter B_WIDTH      = 18,
    parameter C_WIDTH      = 36,
    parameter SUM_WIDTH    = 48,
    parameter RESULT_SHIFT = 0,
    parameter RESULT_WIDTH = 48,
    parameter SUBTRACT     = 0,
    parameter STAGES       = 1    // 1 to 3
)(
    input  wire                           clock,
    input  wire signed [A_WIDTH-1:0]      a,
    input  wire signed [B_WIDTH-1:0]      b,
    input  wire signed [C_WIDTH-1:0]      c,
    output wire signed [RESULT_WIDTH-1:0] result
);
    //--------------------------------------------------------------------------
    // Input registers (AREG/BREG/CREG), used when STAGES >= 2
    //--------------------------------------------------------------------------
    reg signed [A_WIDTH-1:0] a_register;
    reg signed [B_WIDTH-1:0] b_register;
    reg signed [C_WIDTH-1:0] c_register;

    always @(posedge clock) begin
        a_register <= a;
        b_register <= b;
        c_register <= c;
    end

    wire signed [A_WIDTH-1:0] multiplier_a = (STAGES >= 2) ? a_register : a;
    wire signed [B_WIDTH-1:0] multiplier_b = (STAGES >= 2) ? b_register : b;
    wire signed [C_WIDTH-1:0] addend       = (STAGES >= 2) ? c_register : c;

    //--------------------------------------------------------------------------
    // Multiply, with an optional multiplier register (MREG) when STAGES = 3.
    // c waits one extra cycle alongside it so both reach the adder together.
    //--------------------------------------------------------------------------
    wire signed [A_WIDTH+B_WIDTH-1:0] product = multiplier_a * multiplier_b;

    reg signed [A_WIDTH+B_WIDTH-1:0] multiplier_register;
    reg signed [C_WIDTH-1:0]         addend_register;

    always @(posedge clock) begin
        multiplier_register <= product;
        addend_register     <= addend;
    end

    wire signed [A_WIDTH+B_WIDTH-1:0] product_to_add = (STAGES >= 3) ? multiplier_register : product;
    wire signed [C_WIDTH-1:0]         addend_to_add  = (STAGES >= 3) ? addend_register     : addend;

    //--------------------------------------------------------------------------
    // Add / subtract into the output register (PREG), always used
    //--------------------------------------------------------------------------
    reg signed [SUM_WIDTH-1:0] sum;

    always @(posedge clock)
        sum <= SUBTRACT ? addend_to_add - product_to_add : addend_to_add + product_to_add;

    assign result = sum[RESULT_SHIFT +: RESULT_WIDTH];
endmodule
