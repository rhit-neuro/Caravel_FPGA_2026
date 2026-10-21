`timescale 1ns / 1ps
//==============================================================================
// timing_harness  (Vivado implementation only, not used in simulation)
//
// Wraps ONE of the profiled modules in plain flip-flops so that every timing
// path Vivado analyses starts and ends at a register. Without this, the paths
// from the top-level ports into the DSP would be unconstrained.
//
// Both sets of harness flip-flops are marked dont_touch so Vivado cannot fold
// them into the DSP's own registers. That keeps the DSP showing only the
// registers the module under test really has.
//
// OPERATION selects which module is wrapped:
//   0 = dsp_adder
//   1 = dsp_fixed_point_multiplier
//   2 = shift_add_power   (operand_b[4:0] is used as the exponent)
//==============================================================================
module timing_harness #(
    parameter OPERATION     = 0,
    parameter DATA_WIDTH    = 18,
    parameter FRACTION_BITS = 16
)(
    input  wire                  clock,
    input  wire                  reset,
    input  wire                  input_valid,
    input  wire [DATA_WIDTH-1:0] operand_a,
    input  wire [DATA_WIDTH-1:0] operand_b,
    (* dont_touch = "true" *) output reg                  output_valid,   // capture flip-flops,
    (* dont_touch = "true" *) output reg [DATA_WIDTH-1:0] result          // kept out of the DSP
);
    //--------------------------------------------------------------------------
    // Launch flip-flops (kept out of the DSP)
    //--------------------------------------------------------------------------
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_a;
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_b;
    (* dont_touch = "true" *) reg                  launch_valid;

    always @(posedge clock) begin
        launch_operand_a <= operand_a;
        launch_operand_b <= operand_b;
        launch_valid     <= input_valid;
    end

    //--------------------------------------------------------------------------
    // Module under test
    //--------------------------------------------------------------------------
    wire                  module_output_valid;
    wire [DATA_WIDTH-1:0] module_result;

    generate
        if (OPERATION == 0) begin : adder
            dsp_adder #(
                .DATA_WIDTH(DATA_WIDTH)
            ) module_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand_a(launch_operand_a),
                .operand_b(launch_operand_b),
                .output_valid(module_output_valid),
                .result(module_result));
        end else if (OPERATION == 1) begin : multiplier
            dsp_fixed_point_multiplier #(
                .DATA_WIDTH(DATA_WIDTH), .FRACTION_BITS(FRACTION_BITS)
            ) module_under_test (
                .clock(clock), .input_valid(launch_valid),
                .operand_a(launch_operand_a), .operand_b(launch_operand_b),
                .output_valid(module_output_valid), .result(module_result));
        end else begin : power
            shift_add_power #(
                .DATA_WIDTH(DATA_WIDTH), .FRACTION_BITS(FRACTION_BITS), .EXPONENT_WIDTH(5)
            ) module_under_test (
                .clock(clock), .reset(reset), .start(launch_valid),
                .base(launch_operand_a), .exponent(launch_operand_b[4:0]),
                .busy(), .done(module_output_valid), .result(module_result));
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Capture flip-flops (kept out of the DSP)
    //--------------------------------------------------------------------------
    always @(posedge clock) begin
        output_valid <= module_output_valid;
        result       <= module_result;
    end
endmodule
