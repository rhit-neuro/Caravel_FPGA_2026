`timescale 1ns / 1ps
//==============================================================================
// float_power
//
// Computes  result = base ^ exponent  for a floating-point base and an
// unsigned integer exponent, by repeated multiplication:
//     base^exponent = base * base * ... * base   (exponent - 1 multiplies)
// Each multiply goes through float_ip_unit (the IP set up as a multiplier),
// and waits for its answer before starting the next one.
//
// Latency (start pulse -> done pulse), with an L-cycle multiplier:
//   exponent = 0 or 1 :  2 cycles
//   exponent >= 2     :  2 + (exponent - 1) * (L + 2) cycles
//   (1 to load, L + 2 per multiply, 1 to finish; each multiply spends one
//    cycle starting and one cycle collecting the answer, plus the L inside)
//==============================================================================
module float_power #(
    parameter DATA_WIDTH     = 32,   // 16 = half, 32 = single
    parameter EXPONENT_WIDTH = 5
)(
    input  wire                      clock,
    input  wire                      reset,
    input  wire                      start,      // one-cycle pulse: begin with this base/exponent
    input  wire [DATA_WIDTH-1:0]     base,
    input  wire [EXPONENT_WIDTH-1:0] exponent,
    output reg                       busy,       // high while a calculation is running
    output reg                       done,       // one-cycle pulse: result is valid
    output reg  [DATA_WIDTH-1:0]     result
);
    // The value 1.0 (for base^0): sign 0, exponent = bias, mantissa 0
    localparam [DATA_WIDTH-1:0] FLOAT_ONE = (DATA_WIDTH == 16) ? 16'h3C00 : 32'h3F80_0000;

    localparam [1:0] STATE_IDLE     = 2'd0,   // waiting for start
                     STATE_MULTIPLY = 2'd1,   // start one multiply
                     STATE_WAIT     = 2'd2,   // wait for its answer
                     STATE_FINISH   = 2'd3;   // raise done

    reg [1:0]                state;
    reg [DATA_WIDTH-1:0]     saved_base;
    reg [DATA_WIDTH-1:0]     running_power;        // base^k so far
    reg [EXPONENT_WIDTH-1:0] multiplies_remaining;
    reg                      multiply_start;

    wire                  product_valid;
    wire [DATA_WIDTH-1:0] product;

    float_ip_unit #(.DATA_WIDTH(DATA_WIDTH)) multiplier (
        .clock(clock),
        .input_valid(multiply_start),
        .operand_a(running_power),
        .operand_b(saved_base),
        .output_valid(product_valid),
        .result(product)
    );

    always @(posedge clock) begin
        if (reset) begin
            state          <= STATE_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            multiply_start <= 1'b0;
            result         <= 0;
        end else begin
            done           <= 1'b0;   // one-cycle pulses
            multiply_start <= 1'b0;

            case (state)
            STATE_IDLE: if (start) begin
                busy                 <= 1'b1;
                saved_base           <= base;
                running_power        <= (exponent == 0) ? FLOAT_ONE : base;
                multiplies_remaining <= (exponent == 0) ? 0 : exponent - 1;
                state                <= (exponent <= 1) ? STATE_FINISH : STATE_MULTIPLY;
            end

            STATE_MULTIPLY: begin
                multiply_start <= 1'b1;            // running_power * base
                state          <= STATE_WAIT;
            end

            STATE_WAIT: if (product_valid) begin
                running_power        <= product;
                multiplies_remaining <= multiplies_remaining - 1;
                state <= (multiplies_remaining == 1) ? STATE_FINISH : STATE_MULTIPLY;
            end

            STATE_FINISH: begin
                result <= running_power;
                done   <= 1'b1;
                busy   <= 1'b0;
                state  <= STATE_IDLE;
            end
            endcase
        end
    end
endmodule
