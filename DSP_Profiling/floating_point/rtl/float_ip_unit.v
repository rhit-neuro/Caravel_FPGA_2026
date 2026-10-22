`timescale 1ns / 1ps
//==============================================================================
// float_ip_unit
//
// One floating-point operation (add, multiply or divide) using AMD's
// Floating-Point IP, with the same simple interface as the fixed-point
// modules: operands + input_valid in, result + output_valid out.
//
// The IP itself is the module "float_under_test". The build and simulation
// scripts create it fresh for each configuration (operation, precision,
// latency), so this file never changes.
//
// Precision: DATA_WIDTH = 16 (IEEE half) or 32 (IEEE single).
//
// Latency (clock cycles from input_valid to output_valid) is the IP's
// C_Latency setting = its number of pipeline stages. The IP accepts new
// operands every cycle no matter how many stages it has.
//==============================================================================
module float_ip_unit #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clock,
    input  wire                  input_valid,   // high when operand_a/operand_b hold new values
    input  wire [DATA_WIDTH-1:0] operand_a,
    input  wire [DATA_WIDTH-1:0] operand_b,
    output wire                  output_valid,  // high when result holds a new answer
    output wire [DATA_WIDTH-1:0] result
);
    // The IP uses AXI-Stream names: s_axis_* = inputs, m_axis_* = output.
    // Both operands arrive together, so they share one valid signal.
    float_under_test floating_point_ip (
        .aclk                 (clock),
        .s_axis_a_tvalid      (input_valid),
        .s_axis_a_tdata       (operand_a),
        .s_axis_b_tvalid      (input_valid),
        .s_axis_b_tdata       (operand_b),
        .m_axis_result_tvalid (output_valid),
        .m_axis_result_tdata  (result)
    );
endmodule
