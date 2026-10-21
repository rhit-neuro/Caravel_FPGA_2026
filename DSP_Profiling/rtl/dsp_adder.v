`timescale 1ns / 1ps
//==============================================================================
// dsp_adder
//
// Adds two signed numbers using the adder inside one DSP48E2 slice.
//
// PIPELINE_STAGES = clock cycles from operands applied to result valid:
//   1 : sum goes straight into the DSP output register (PREG)
//   2 : operands first go into the DSP input registers (AREG/BREG/CREG),
//       then the sum into PREG. Shorter paths, so it can run at a faster clock.
//
// The DSP48E2 adder is 48 bits wide, so any DATA_WIDTH up to 48 fits in one DSP.
//==============================================================================
(* use_dsp = "yes" *)   // tell Vivado to build this adder in a DSP, not in LUTs
module dsp_adder #(
    parameter DATA_WIDTH      = 18,
    parameter PIPELINE_STAGES = 1    // 1 or 2
)(
    input  wire                         clock,
    input  wire                         input_valid,   // high when operand_a/operand_b hold new values
    input  wire signed [DATA_WIDTH-1:0] operand_a,
    input  wire signed [DATA_WIDTH-1:0] operand_b,
    output wire                         output_valid,  // high when result holds a new sum
    output reg  signed [DATA_WIDTH-1:0] result
);
    //--------------------------------------------------------------------------
    // Input registers (DSP AREG/BREG/CREG), used only when PIPELINE_STAGES = 2
    //--------------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] registered_operand_a, registered_operand_b;

    always @(posedge clock) begin
        registered_operand_a <= operand_a;
        registered_operand_b <= operand_b;
    end

    wire signed [DATA_WIDTH-1:0] adder_input_a = (PIPELINE_STAGES == 2) ? registered_operand_a : operand_a;
    wire signed [DATA_WIDTH-1:0] adder_input_b = (PIPELINE_STAGES == 2) ? registered_operand_b : operand_b;

    //--------------------------------------------------------------------------
    // Add, and store the sum in the DSP output register (PREG)
    //--------------------------------------------------------------------------
    always @(posedge clock)
        result <= adder_input_a + adder_input_b;

    //--------------------------------------------------------------------------
    // output_valid = input_valid delayed by PIPELINE_STAGES cycles
    //--------------------------------------------------------------------------
    reg [PIPELINE_STAGES-1:0] valid_delay_line = 0;

    always @(posedge clock)
        valid_delay_line <= (valid_delay_line << 1) | input_valid;

    assign output_valid = valid_delay_line[PIPELINE_STAGES-1];
endmodule
