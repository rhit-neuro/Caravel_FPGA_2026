`timescale 1ns / 1ps
//==============================================================================
// timing_harness  (Vivado builds only, not used in simulation)
//
// Wraps ONE profiled module in plain flip-flops so every timing path Vivado
// checks starts and ends at a register. The flip-flops are marked dont_touch
// so Vivado can't fold them into the DSP/BRAM and add stages the module
// doesn't have.
//
// OPERATION selects the module:
//   0 = dsp_adder
//   1 = dsp_fixed_point_multiplier
//   2 = shift_add_power   (operand_b[4:0] is the exponent)
//   3 = bram_memory       (operand_a = address, operand_b = write data)
//   4 = uram_memory       (operand_a = address, operand_b = write data)
//   5 = shift_subtract_divider (operand_a / operand_b)
// PIPELINE_STAGES is passed to the module (for the memories: read stages).
//==============================================================================
module timing_harness #(
    parameter OPERATION       = 0,
    parameter DATA_WIDTH      = 18,
    parameter FRACTION_BITS   = 16,
    parameter PIPELINE_STAGES = 1
)(
    input  wire                  clock,
    input  wire                  reset,
    input  wire                  input_valid,    // start / read_enable for the BRAM
    input  wire                  write_enable,   // BRAM only
    input  wire [DATA_WIDTH-1:0] operand_a,
    input  wire [DATA_WIDTH-1:0] operand_b,
    (* dont_touch = "true" *) output reg                  output_valid,   // capture flip-flops,
    (* dont_touch = "true" *) output reg [DATA_WIDTH-1:0] result          // kept out of the DSP/BRAM
);
    //--------------------------------------------------------------------------
    // Launch flip-flops (kept out of the DSP/BRAM)
    //--------------------------------------------------------------------------
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_a;
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_b;
    (* dont_touch = "true" *) reg                  launch_valid;
    (* dont_touch = "true" *) reg                  launch_write_enable;

    always @(posedge clock) begin
        launch_operand_a    <= operand_a;
        launch_operand_b    <= operand_b;
        launch_valid        <= input_valid;
        launch_write_enable <= write_enable;
    end

    //--------------------------------------------------------------------------
    // Module under test
    //--------------------------------------------------------------------------
    wire                  module_output_valid;
    wire [DATA_WIDTH-1:0] module_result;

    generate
        if (OPERATION == 0) begin : adder
            dsp_adder #(
                .DATA_WIDTH(DATA_WIDTH), .PIPELINE_STAGES(PIPELINE_STAGES)
            ) module_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand_a(launch_operand_a),
                .operand_b(launch_operand_b),
                .output_valid(module_output_valid),
                .result(module_result));
        end else if (OPERATION == 1) begin : multiplier
            dsp_fixed_point_multiplier #(
                .DATA_WIDTH(DATA_WIDTH), .FRACTION_BITS(FRACTION_BITS), .PIPELINE_STAGES(PIPELINE_STAGES)
            ) module_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand_a(launch_operand_a),
                .operand_b(launch_operand_b),
                .output_valid(module_output_valid),
                .result(module_result));
        end else if (OPERATION == 2) begin : power
            shift_add_power #(
                .DATA_WIDTH(DATA_WIDTH), .FRACTION_BITS(FRACTION_BITS), .EXPONENT_WIDTH(5)
            ) module_under_test (
                .clock(clock),
                .reset(reset),
                .start(launch_valid),
                .base(launch_operand_a),
                .exponent(launch_operand_b[4:0]),
                .busy(),
                .done(module_output_valid),
                .result(module_result));
        end else if (OPERATION == 5) begin : divider
            shift_subtract_divider #(
                .DATA_WIDTH(DATA_WIDTH), .FRACTION_BITS(FRACTION_BITS)
            ) module_under_test (
                .clock(clock),
                .reset(reset),
                .start(launch_valid),
                .dividend(launch_operand_a),
                .divisor(launch_operand_b),
                .busy(),
                .done(module_output_valid),
                .quotient(module_result),
                .divide_by_zero());
        end else if (OPERATION == 4) begin : ultra_memory
            uram_memory #(
                .DATA_WIDTH(DATA_WIDTH), .ADDRESS_WIDTH(12), .READ_PIPELINE_STAGES(PIPELINE_STAGES)
            ) module_under_test (
                .clock(clock),
                .write_enable(launch_write_enable),
                .write_address(launch_operand_a[11:0]),
                .write_data(launch_operand_b),
                .read_enable(launch_valid),
                .read_address(launch_operand_a[11:0]),
                .read_valid(module_output_valid),
                .read_data(module_result));
        end else begin : memory
            bram_memory #(
                .DATA_WIDTH(DATA_WIDTH), .ADDRESS_WIDTH(10), .READ_PIPELINE_STAGES(PIPELINE_STAGES)
            ) module_under_test (
                .clock(clock),
                .write_enable(launch_write_enable),
                .write_address(launch_operand_a[9:0]),
                .write_data(launch_operand_b),
                .read_enable(launch_valid),
                .read_address(launch_operand_a[9:0]),
                .read_valid(module_output_valid),
                .read_data(module_result));
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Capture flip-flops
    //--------------------------------------------------------------------------
    always @(posedge clock) begin
        output_valid <= module_output_valid;
        result       <= module_result;
    end
endmodule
