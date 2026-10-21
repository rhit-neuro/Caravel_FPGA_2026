`timescale 1ns / 1ps
//==============================================================================
// shift_subtract_divider
//
// Computes  quotient = dividend / divisor  for signed fixed-point numbers
// (DATA_WIDTH bits, FRACTION_BITS after the binary point), using long division
// in binary: one quotient bit per clock cycle, no multiplier.
//
// How it works
//   - Fixed point: dividing two numbers with FRACTION_BITS fraction bits would
//     cancel the fraction bits, so the dividend is shifted left by
//     FRACTION_BITS first:  quotient = (|dividend| << FRACTION_BITS) / |divisor|
//   - Long division, one bit per cycle, highest bit first:
//       remainder = (remainder << 1) | next dividend bit
//       if remainder >= |divisor|:  remainder -= |divisor|, quotient bit = 1
//       else:                                               quotient bit = 0
//   - The subtraction is placed in a DSP48E2 (use_dsp attribute).
//   - Signs are handled separately: the result is negative when exactly one
//     of dividend/divisor is negative.
//
// Latency (start pulse -> done pulse):
//   2 + DATA_WIDTH + FRACTION_BITS clock cycles
//   (1 to load, one per dividend bit, 1 to apply the sign)
//
// Limitations: results are truncated, not rounded or saturated; keep the
// quotient inside the fixed-point range. Dividing by zero sets
// divide_by_zero and returns the largest positive value.
//==============================================================================
module shift_subtract_divider #(
    parameter DATA_WIDTH    = 18,
    parameter FRACTION_BITS = 16
)(
    input  wire                         clock,
    input  wire                         reset,
    input  wire                         start,            // one-cycle pulse: begin with these inputs
    input  wire signed [DATA_WIDTH-1:0] dividend,
    input  wire signed [DATA_WIDTH-1:0] divisor,
    output reg                          busy,             // high while dividing
    output reg                          done,             // one-cycle pulse: quotient is valid
    output reg  signed [DATA_WIDTH-1:0] quotient,
    output reg                          divide_by_zero
);
    localparam DIVIDEND_BITS = DATA_WIDTH + FRACTION_BITS;   // |dividend| << FRACTION_BITS

    localparam [1:0] STATE_IDLE   = 2'd0,   // waiting for start
                     STATE_DIVIDE = 2'd1,   // one quotient bit per cycle
                     STATE_FINISH = 2'd2;   // apply sign, raise done

    reg [1:0] state;

    //--------------------------------------------------------------------------
    // Working registers
    //--------------------------------------------------------------------------
    reg [DIVIDEND_BITS-1:0] dividend_bits;        // shifted left one bit per cycle
    reg [DATA_WIDTH-1:0]    divisor_magnitude;    // |divisor|
    reg [DATA_WIDTH:0]      remainder;            // one bit wider than the divisor
    reg [DIVIDEND_BITS-1:0] quotient_bits;        // filled in from the right
    reg [$clog2(DIVIDEND_BITS+1)-1:0] bits_left;
    reg                     result_is_negative;

    wire [DATA_WIDTH-1:0] dividend_absolute_value = dividend[DATA_WIDTH-1] ? -dividend : dividend;
    wire [DATA_WIDTH-1:0] divisor_absolute_value  = divisor[DATA_WIDTH-1]  ? -divisor  : divisor;

    //--------------------------------------------------------------------------
    // One long-division step: bring down the next dividend bit, try subtracting
    //--------------------------------------------------------------------------
    wire [DATA_WIDTH:0] remainder_with_next_bit = {remainder[DATA_WIDTH-1:0], dividend_bits[DIVIDEND_BITS-1]};

    (* use_dsp = "yes" *)
    wire [DATA_WIDTH+1:0] trial_difference = {1'b0, remainder_with_next_bit} - {2'b00, divisor_magnitude};

    wire divisor_fits = !trial_difference[DATA_WIDTH+1];   // no borrow: remainder >= divisor

    //--------------------------------------------------------------------------
    // State machine
    //--------------------------------------------------------------------------
    always @(posedge clock) begin
        if (reset) begin
            state          <= STATE_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            quotient       <= 0;
            divide_by_zero <= 1'b0;
        end else begin
            done <= 1'b0;   // done is a one-cycle pulse

            case (state)
            //------------------------------------------------------------------
            STATE_IDLE: if (start) begin
                busy               <= 1'b1;
                dividend_bits      <= {dividend_absolute_value, {FRACTION_BITS{1'b0}}};
                divisor_magnitude  <= divisor_absolute_value;
                remainder          <= 0;
                quotient_bits      <= 0;
                bits_left          <= DIVIDEND_BITS;
                result_is_negative <= dividend[DATA_WIDTH-1] ^ divisor[DATA_WIDTH-1];
                divide_by_zero     <= (divisor == 0);
                state              <= STATE_DIVIDE;
            end

            //------------------------------------------------------------------
            STATE_DIVIDE: begin
                if (divisor_fits) remainder <= trial_difference[DATA_WIDTH:0];
                else              remainder <= remainder_with_next_bit;
                quotient_bits <= {quotient_bits[DIVIDEND_BITS-2:0], divisor_fits};
                dividend_bits <= dividend_bits << 1;
                bits_left     <= bits_left - 1;
                if (bits_left == 1) state <= STATE_FINISH;
            end

            //------------------------------------------------------------------
            STATE_FINISH: begin
                if (divide_by_zero)
                    quotient <= {1'b0, {(DATA_WIDTH-1){1'b1}}};   // largest positive value
                else
                    quotient <= result_is_negative ? -quotient_bits[DATA_WIDTH-1:0]
                                                   :  quotient_bits[DATA_WIDTH-1:0];
                done  <= 1'b1;
                busy  <= 1'b0;
                state <= STATE_IDLE;
            end

            default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
