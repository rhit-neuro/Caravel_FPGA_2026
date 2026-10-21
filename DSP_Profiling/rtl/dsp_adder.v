`timescale 1ns / 1ps
//==============================================================================
// dsp_adder
//
// Adds two signed numbers using the adder inside one DSP48E2 slice.
// Latency: 1 clock cycle. The operands go straight into the DSP adder and the
// sum is captured in the DSP's output register (PREG).
//
// Width: the DSP48E2 adder is 48 bits wide, so any DATA_WIDTH up to 48 fits in
// a single DSP and takes the same time. The default of 18 matches the
// Q2.16 results of the 18x18 multiplier.
//
// Fixed point: addition works for any fixed-point format without extra logic,
// as long as both operands have the same number of fraction bits.
//==============================================================================
(* use_dsp = "yes" *)   // tell Vivado to build this adder in a DSP, not in LUTs
module dsp_adder #(
    parameter DATA_WIDTH = 18
)(
    input  wire                         clock,
    input  wire                         input_valid,   // high when operand_a/operand_b hold new values
    input  wire signed [DATA_WIDTH-1:0] operand_a,
    input  wire signed [DATA_WIDTH-1:0] operand_b,
    output reg                          output_valid,  // high when result holds a new sum
    output reg  signed [DATA_WIDTH-1:0] result
);
    always @(posedge clock) begin
        result       <= operand_a + operand_b;   // DSP adder -> output register (PREG)
        output_valid <= input_valid;             // result is ready one cycle after the operands
    end
endmodule
