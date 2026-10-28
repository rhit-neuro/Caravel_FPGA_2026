`timescale 1ns / 1ps
//==============================================================================
// float_timing_harness  (Vivado builds only, not used in simulation)
//
// Wraps ONE floating-point unit in plain flip-flops so every timing path
// Vivado checks starts and ends at a register. The flip-flops are marked
// dont_touch so Vivado can't fold them into the DSPs.
//
// UNIT selects what is wrapped:
//   0 = float_ip_unit    (the IP: add, multiply or divide, set by the script)
//   1 = float_power      (x^n using the IP as a multiplier; operand_b[4:0] = n)
//   2 = current design FloatingAddition        (single precision only)
//   3 = current design FloatingMultiplication  (single precision only)
//   4 = current design LUT_MAC_Module, a*b + c (single precision only)
//   5 = float_ip_unit with one operand (the IP set up as a reciprocal, 1/a)
//   6 = float_newton_raphson_reciprocal, 1/a (SEED_BITS, ITERATIONS and
//       MULTIPLY_STAGES are only used by this one)
//==============================================================================
module float_timing_harness #(
    parameter UNIT       = 0,
    parameter DATA_WIDTH      = 32,   // 16 = half, 32 = single
    parameter SEED_BITS       = 7,
    parameter ITERATIONS      = 2,
    parameter MULTIPLY_STAGES = 1
)(
    input  wire                  clock,
    input  wire                  reset,
    input  wire                  input_valid,
    input  wire [DATA_WIDTH-1:0] operand_a,
    input  wire [DATA_WIDTH-1:0] operand_b,
    input  wire [DATA_WIDTH-1:0] operand_c,
    (* dont_touch = "true" *) output reg                  output_valid,   // capture flip-flops
    (* dont_touch = "true" *) output reg [DATA_WIDTH-1:0] result
);
    //--------------------------------------------------------------------------
    // Launch flip-flops
    //--------------------------------------------------------------------------
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_a;
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_b;
    (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] launch_operand_c;
    (* dont_touch = "true" *) reg                  launch_valid;

    always @(posedge clock) begin
        launch_operand_a <= operand_a;
        launch_operand_b <= operand_b;
        launch_operand_c <= operand_c;
        launch_valid     <= input_valid;
    end

    //--------------------------------------------------------------------------
    // Unit under test
    //--------------------------------------------------------------------------
    wire                  unit_output_valid;
    wire [DATA_WIDTH-1:0] unit_result;

    generate
        if (UNIT == 0) begin : ip_operation
            float_ip_unit #(.DATA_WIDTH(DATA_WIDTH)) unit_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand_a(launch_operand_a),
                .operand_b(launch_operand_b),
                .output_valid(unit_output_valid),
                .result(unit_result));
        end else if (UNIT == 1) begin : power
            float_power #(.DATA_WIDTH(DATA_WIDTH), .EXPONENT_WIDTH(5)) unit_under_test (
                .clock(clock),
                .reset(reset),
                .start(launch_valid),
                .base(launch_operand_a),
                .exponent(launch_operand_b[4:0]),
                .busy(),
                .done(unit_output_valid),
                .result(unit_result));
        end else if (UNIT == 5) begin : ip_reciprocal
            float_ip_unit #(.DATA_WIDTH(DATA_WIDTH), .OPERANDS(1)) unit_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand_a(launch_operand_a),
                .operand_b(launch_operand_b),
                .output_valid(unit_output_valid),
                .result(unit_result));
        end else if (UNIT == 6) begin : newton_raphson_reciprocal
            float_newton_raphson_reciprocal #(
                .DATA_WIDTH(DATA_WIDTH), .SEED_BITS(SEED_BITS),
                .ITERATIONS(ITERATIONS), .MULTIPLY_STAGES(MULTIPLY_STAGES)
            ) unit_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand(launch_operand_a),
                .output_valid(unit_output_valid),
                .result(unit_result));
        end else begin : current_design
            current_design_float_unit #(.OPERATION(UNIT - 2)) unit_under_test (
                .clock(clock),
                .input_valid(launch_valid),
                .operand_a(launch_operand_a),
                .operand_b(launch_operand_b),
                .operand_c(launch_operand_c),
                .output_valid(unit_output_valid),
                .result(unit_result));
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Capture flip-flops
    //--------------------------------------------------------------------------
    always @(posedge clock) begin
        output_valid <= unit_output_valid;
        result       <= unit_result;
    end
endmodule
