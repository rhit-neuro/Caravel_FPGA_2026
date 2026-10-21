`timescale 1ns / 1ps
//==============================================================================
// dsp_fixed_point_multiplier
//
// Multiplies two signed fixed-point numbers using one DSP48E2 slice.
// The DSP48E2 multiplier is 27 x 18 bits, so 16x16 and 18x18 both fit in one DSP.
//
// Fixed-point format: DATA_WIDTH total bits, FRACTION_BITS after the binary point.
//   DATA_WIDTH = 18, FRACTION_BITS = 16  ->  Q2.16  (range -2 .. +2)
//   DATA_WIDTH = 16, FRACTION_BITS = 12  ->  Q4.12  (range -8 .. +8)
// The full product has 2*FRACTION_BITS fraction bits, so the result keeps the
// bits starting at FRACTION_BITS (truncation, wiring only, no extra logic).
//
// PIPELINE_STAGES = clock cycles from operands applied to result valid.
// Each stage turns on one more register inside the DSP:
//   1 : output register                                (PREG)
//   2 : input register + output register               (AREG/BREG + PREG)
//   3 : input + multiplier + output registers          (AREG/BREG + MREG + PREG)
//   4 : two input registers + multiplier + output      (AREG/BREG x2 + MREG + PREG)
// More stages = shorter paths between registers = faster clock possible.
//==============================================================================
(* use_dsp = "yes" *)   // tell Vivado to build this multiplier in a DSP
module dsp_fixed_point_multiplier #(
    parameter DATA_WIDTH      = 18,
    parameter FRACTION_BITS   = 16,
    parameter PIPELINE_STAGES = 1    // 1 to 4
)(
    input  wire                         clock,
    input  wire                         input_valid,   // high when operand_a/operand_b hold new values
    input  wire signed [DATA_WIDTH-1:0] operand_a,
    input  wire signed [DATA_WIDTH-1:0] operand_b,
    output wire                         output_valid,  // high when result holds a new product
    output wire signed [DATA_WIDTH-1:0] result
);
    localparam PRODUCT_WIDTH         = 2 * DATA_WIDTH;
    localparam INPUT_REGISTER_STAGES = (PIPELINE_STAGES == 4) ? 2 :
                                       (PIPELINE_STAGES >= 2) ? 1 : 0;
    localparam USE_MULTIPLIER_REGISTER = (PIPELINE_STAGES >= 3);

    //--------------------------------------------------------------------------
    // Input registers (DSP AREG/BREG): 0, 1 or 2 of them
    //--------------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] operand_a_stage1, operand_a_stage2;
    reg signed [DATA_WIDTH-1:0] operand_b_stage1, operand_b_stage2;

    always @(posedge clock) begin
        operand_a_stage1 <= operand_a;
        operand_b_stage1 <= operand_b;
        operand_a_stage2 <= operand_a_stage1;
        operand_b_stage2 <= operand_b_stage1;
    end

    wire signed [DATA_WIDTH-1:0] multiplier_input_a =
        (INPUT_REGISTER_STAGES == 2) ? operand_a_stage2 :
        (INPUT_REGISTER_STAGES == 1) ? operand_a_stage1 : operand_a;

    wire signed [DATA_WIDTH-1:0] multiplier_input_b =
        (INPUT_REGISTER_STAGES == 2) ? operand_b_stage2 :
        (INPUT_REGISTER_STAGES == 1) ? operand_b_stage1 : operand_b;

    //--------------------------------------------------------------------------
    // Multiply, with an optional multiplier register (DSP MREG)
    //--------------------------------------------------------------------------
    wire signed [PRODUCT_WIDTH-1:0] full_product = multiplier_input_a * multiplier_input_b;

    reg signed [PRODUCT_WIDTH-1:0] multiplier_register;

    always @(posedge clock)
        multiplier_register <= full_product;

    wire signed [PRODUCT_WIDTH-1:0] product_before_output_register =
        USE_MULTIPLIER_REGISTER ? multiplier_register : full_product;

    //--------------------------------------------------------------------------
    // Output register (DSP PREG), always used
    //--------------------------------------------------------------------------
    reg signed [PRODUCT_WIDTH-1:0] output_register;

    always @(posedge clock)
        output_register <= product_before_output_register;

    // Drop the extra FRACTION_BITS low bits to return to the input format
    assign result = output_register[FRACTION_BITS +: DATA_WIDTH];

    //--------------------------------------------------------------------------
    // output_valid = input_valid delayed by PIPELINE_STAGES cycles
    //--------------------------------------------------------------------------
    reg [PIPELINE_STAGES-1:0] valid_delay_line = 0;

    always @(posedge clock)
        valid_delay_line <= (valid_delay_line << 1) | input_valid;

    assign output_valid = valid_delay_line[PIPELINE_STAGES-1];
endmodule
