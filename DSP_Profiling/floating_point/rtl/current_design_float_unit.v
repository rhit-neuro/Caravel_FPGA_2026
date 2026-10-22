`timescale 1ns / 1ps
//==============================================================================
// current_design_float_unit
//
// The synaptic module's own single-precision float units (copied unchanged
// into current_design/), with an output register so they can be timed:
//   OPERATION 0 = FloatingAddition       result = a + b
//   OPERATION 1 = FloatingMultiplication result = a * b
//   OPERATION 2 = LUT_MAC_Module         result = a * b + c   (used by the
//                                        h/g accumulators)
// The units themselves are combinational, so the latency is 1 clock cycle.
//==============================================================================
module current_design_float_unit #(
    parameter OPERATION = 0
)(
    input  wire        clock,
    input  wire        input_valid,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire [31:0] operand_c,      // MAC only
    output reg         output_valid,
    output reg  [31:0] result
);
    wire [31:0] sum, product, multiply_add;

    FloatingAddition       adder      (.A(operand_a), .B(operand_b), .Exception(), .result(sum));
    FloatingMultiplication multiplier (.A(operand_a), .B(operand_b), .Exception(), .Overflow(),
                                       .Underflow(), .result(product));
    LUT_MAC_Module         mac        (.M_value(operand_a), .X_value(operand_b), .B_value(operand_c),
                                       .Exception(), .Overflow(), .Underflow(), .result(multiply_add));

    always @(posedge clock) begin
        result       <= (OPERATION == 0) ? sum : (OPERATION == 1) ? product : multiply_add;
        output_valid <= input_valid;
    end
endmodule
