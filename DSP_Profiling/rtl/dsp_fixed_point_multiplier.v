`timescale 1ns / 1ps
//==============================================================================
// dsp_fixed_point_multiplier
//
// Multiplies two signed fixed-point numbers using one DSP48E2 slice.
// Latency: 1 clock cycle. The operands go straight into the DSP multiplier and
// the product is captured in the DSP's output register (PREG).
// The DSP48E2 multiplier is 27 x 18 bits, so both 16x16 and 18x18 fit in one DSP.
//
// Fixed-point format: DATA_WIDTH total bits, FRACTION_BITS of them after the
// binary point.  Examples:
//   DATA_WIDTH = 18, FRACTION_BITS = 16  ->  Q2.16  (range -2 .. +2)
//   DATA_WIDTH = 16, FRACTION_BITS = 12  ->  Q4.12  (range -8 .. +8)
//
// Why the result is shifted: multiplying two numbers that each have
// FRACTION_BITS fraction bits gives a product with 2*FRACTION_BITS fraction
// bits. Selecting the bits starting at FRACTION_BITS brings the result back to
// the input format. This is wiring only (truncation, no rounding or
// saturation), so it adds no logic or delay.
//==============================================================================
(* use_dsp = "yes" *)   // tell Vivado to build this multiplier in a DSP
module dsp_fixed_point_multiplier #(
    parameter DATA_WIDTH    = 18,
    parameter FRACTION_BITS = 16
)(
    input  wire                         clock,
    input  wire                         input_valid,   // high when operand_a/operand_b hold new values
    input  wire signed [DATA_WIDTH-1:0] operand_a,
    input  wire signed [DATA_WIDTH-1:0] operand_b,
    output reg                          output_valid,  // high when result holds a new product
    output wire signed [DATA_WIDTH-1:0] result
);
    localparam PRODUCT_WIDTH = 2 * DATA_WIDTH;

    // Full-precision product, captured in the DSP output register (PREG)
    reg signed [PRODUCT_WIDTH-1:0] product_register;

    always @(posedge clock) begin
        product_register <= operand_a * operand_b;
        output_valid     <= input_valid;   // result is ready one cycle after the operands
    end

    // Drop the extra FRACTION_BITS low bits to return to the input format
    assign result = product_register[FRACTION_BITS +: DATA_WIDTH];
endmodule
