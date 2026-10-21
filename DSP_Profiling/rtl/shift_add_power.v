`timescale 1ns / 1ps
//==============================================================================
// shift_add_power
//
// Computes  result = base ^ exponent  with shift-and-add, using no hardware
// multiplier. base and result are signed fixed point (DATA_WIDTH bits,
// FRACTION_BITS after the binary point). exponent is an unsigned integer.
//
// How it works
//   - The power is built by repeated multiplication:
//       base^exponent = base * base * ... * base   (exponent - 1 multiplies)
//   - Each multiply is done one bit per clock cycle (shift-and-add):
//       for each bit of |base|, lowest bit first:
//           if the bit is 1:  sum = sum + shifted_multiplicand
//           shifted_multiplicand = shifted_multiplicand << 1
//     so one multiply takes DATA_WIDTH clock cycles.
//   - The add in that loop is placed in a DSP48E2 (use_dsp attribute).
//   - The math is done on magnitudes. The sign is applied at the end: the result
//     is negative only when base is negative and exponent is odd.
//
// Latency (start pulse -> done pulse):
//   exponent = 0 or 1 :  2 clock cycles
//   exponent >= 2     :  2 + (exponent - 1) * DATA_WIDTH clock cycles
//
// Limitation: results are truncated, not saturated. Keep |base^exponent|
// inside the fixed-point range (below 2.0 for Q2.16) or the result wraps around.
//==============================================================================
module shift_add_power #(
    parameter DATA_WIDTH     = 18,
    parameter FRACTION_BITS  = 16,
    parameter EXPONENT_WIDTH = 5
)(
    input  wire                          clock,
    input  wire                          reset,
    input  wire                          start,     // one-cycle pulse: begin with this base/exponent
    input  wire signed [DATA_WIDTH-1:0]  base,
    input  wire [EXPONENT_WIDTH-1:0]     exponent,
    output reg                           busy,      // high while a calculation is running
    output reg                           done,      // one-cycle pulse: result is valid
    output reg  signed [DATA_WIDTH-1:0]  result
);
    localparam PRODUCT_WIDTH = 2 * DATA_WIDTH;

    // The value 1.0 in this fixed-point format (needed for base^0)
    localparam [DATA_WIDTH-1:0] FIXED_POINT_ONE = 1 << FRACTION_BITS;

    // State machine states
    localparam [1:0] STATE_IDLE     = 2'd0,   // waiting for start
                     STATE_MULTIPLY = 2'd1,   // running shift-and-add multiplies
                     STATE_FINISH   = 2'd2;   // apply sign, raise done

    reg [1:0] state;

    //--------------------------------------------------------------------------
    // Working registers
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0]     base_magnitude;        // |base|, reused for every multiply
    reg [DATA_WIDTH-1:0]     multiplier_bits;       // |base|, shifted right one bit per cycle
    reg [PRODUCT_WIDTH-1:0]  shifted_multiplicand;  // running power, shifted left one bit per cycle
    (* use_dsp = "yes" *)
    reg [PRODUCT_WIDTH-1:0]  partial_product_sum;   // shift-and-add accumulator (built in a DSP)
    reg [DATA_WIDTH-1:0]     running_power;         // |base|^k so far
    reg [EXPONENT_WIDTH-1:0] multiplies_remaining;
    reg [$clog2(DATA_WIDTH+1)-1:0] bit_index;       // which multiplier bit is being processed
    reg                      result_is_negative;

    wire [DATA_WIDTH-1:0] base_absolute_value = base[DATA_WIDTH-1] ? -base : base;

    //--------------------------------------------------------------------------
    // One shift-and-add step: add the shifted multiplicand if the current
    // multiplier bit is 1.
    //--------------------------------------------------------------------------
    wire [PRODUCT_WIDTH-1:0] next_partial_product_sum =
        partial_product_sum + (multiplier_bits[0] ? shifted_multiplicand : {PRODUCT_WIDTH{1'b0}});

    // Finished product, shifted back to the input fixed-point format
    wire [DATA_WIDTH-1:0] product_in_fixed_point = next_partial_product_sum[FRACTION_BITS +: DATA_WIDTH];

    //--------------------------------------------------------------------------
    // State machine
    //--------------------------------------------------------------------------
    always @(posedge clock) begin
        if (reset) begin
            state  <= STATE_IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= 0;
        end else begin
            done <= 1'b0;   // done is a one-cycle pulse

            case (state)
            //------------------------------------------------------------------
            STATE_IDLE: if (start) begin
                busy                 <= 1'b1;
                base_magnitude       <= base_absolute_value;
                multiplier_bits      <= base_absolute_value;
                shifted_multiplicand <= base_absolute_value;
                partial_product_sum  <= 0;
                bit_index            <= 0;
                result_is_negative   <= base[DATA_WIDTH-1] & exponent[0];   // negative base, odd exponent

                // base^0 = 1.0, base^1 = base, otherwise start from base
                running_power        <= (exponent == 0) ? FIXED_POINT_ONE : base_absolute_value;
                multiplies_remaining <= (exponent == 0) ? 0 : exponent - 1;
                state                <= (exponent <= 1) ? STATE_FINISH : STATE_MULTIPLY;
            end

            //------------------------------------------------------------------
            STATE_MULTIPLY: begin
                if (bit_index == DATA_WIDTH - 1) begin
                    // Last bit of this multiply: store the product and set up
                    // the next multiply (running_power * |base|).
                    running_power        <= product_in_fixed_point;
                    multiplies_remaining <= multiplies_remaining - 1;
                    partial_product_sum  <= 0;
                    bit_index            <= 0;
                    multiplier_bits      <= base_magnitude;
                    shifted_multiplicand <= product_in_fixed_point;

                    if (multiplies_remaining == 1)
                        state <= STATE_FINISH;
                end else begin
                    // Normal step: accumulate, then move to the next bit
                    partial_product_sum  <= next_partial_product_sum;
                    shifted_multiplicand <= shifted_multiplicand << 1;
                    multiplier_bits      <= multiplier_bits >> 1;
                    bit_index            <= bit_index + 1;
                end
            end

            //------------------------------------------------------------------
            STATE_FINISH: begin
                result <= result_is_negative ? -running_power : running_power;
                done   <= 1'b1;
                busy   <= 1'b0;
                state  <= STATE_IDLE;
            end

            default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
