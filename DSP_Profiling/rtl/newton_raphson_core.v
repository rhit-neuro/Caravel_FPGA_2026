`timescale 1ns / 1ps
//==============================================================================
// newton_raphson_core
//
// reciprocal ~= 1 / divisor, for a normalized divisor 0.5 <= d < 1, using a
// small seed table and ITERATIONS Newton-Raphson steps. Fully pipelined: a new
// divisor can go in every clock cycle. Shared by the fixed-point
// (newton_raphson_reciprocal) and floating-point (float_newton_raphson_reciprocal)
// reciprocal units, which do the normalizing around it.
//
// Number formats (unsigned):
//   divisor    : D_BITS fraction bits, top bit always 1  (value 0.5 .. 1)
//   reciprocal : 1 integer bit + Y_BITS fraction bits    (value 1 .. 2)
//
// How it works
//   1. Seed: the SEED_BITS divisor bits after the top bit pick one of
//      2^SEED_BITS intervals [a, b); the table holds y0 = 2 / (a + b), which
//      makes the worst starting error |1 - d*y0| as small as possible, about
//      2^-(SEED_BITS+1). Entries have SEED_BITS + 3 fraction bits.
//   2. Each Newton-Raphson step doubles the number of correct bits:
//          e      = 1 - d * y          (multiply-subtract, one DSP op)
//          y_next = y + y * e          (multiply-add, one DSP op)
//      This is the usual y * (2 - d*y), rearranged so the second multiply
//      only sees the small error e.
//   3. Each step works only at the precision it can deliver: y goes in
//      truncated to (bits already correct + 2), e and y_next keep about twice
//      that, and y * e uses only as many bits of y as e can affect. Early
//      steps are therefore narrow (one DSP each); only the last step is full
//      width. The last step always produces Y_BITS fraction bits.
//   All truncations round down, so the result is never above 1/d.
//
// Accuracy: within about 5 units of 2^-Y_BITS for the settings used here
// (checked bit for bit against a Python model). The wrappers use 2 or 3
// guard bits (Y_BITS > bits they keep), so their results are within 1 LSB.
//
// Latency (input_valid -> output_valid): 1 + 2 * ITERATIONS * MULTIPLY_STAGES
//   (1 for the seed table, then 2 multiply ops per step, MULTIPLY_STAGES each)
//
// input_tag travels alongside each divisor and comes out with its result,
// so the wrappers can carry signs, shifts and flags through the pipeline.
//==============================================================================
module newton_raphson_core #(
    parameter D_BITS          = 18,
    parameter Y_BITS          = 20,
    parameter SEED_BITS       = 9,
    parameter ITERATIONS      = 1,
    parameter MULTIPLY_STAGES = 1,   // 1 to 3, register stages per multiply op
    parameter TAG_WIDTH       = 1
)(
    input  wire                 clock,
    input  wire                 input_valid,
    input  wire [D_BITS-1:0]    divisor,
    input  wire [TAG_WIDTH-1:0] input_tag,
    output wire                 output_valid,
    output wire [Y_BITS:0]      reciprocal,
    output wire [TAG_WIDTH-1:0] output_tag
);
    localparam GUARD_BITS = 2;
    localparam SEED_FRACTION_BITS = SEED_BITS + 3;

    //--------------------------------------------------------------------------
    // Precision plan, one set of widths per step (Python model: plan()).
    //   field 0: bits already correct before the step (|e| < 2^-this)
    //   field 1: fraction bits of y going into the step
    //   field 2: fraction bits of e and of y_next
    //   field 3: fraction bits of y used in y * e
    //--------------------------------------------------------------------------
    function integer plan(input integer step, input integer field);
        integer i, correct_bits, input_bits, work_bits, correction_bits;
        begin
            correct_bits = SEED_BITS + 1;
            plan = 0;
            for (i = 0; i <= step; i = i + 1) begin
                work_bits       = (i == ITERATIONS - 1)                 ? Y_BITS :
                                  (2 * correct_bits + GUARD_BITS < Y_BITS) ? 2 * correct_bits + GUARD_BITS : Y_BITS;
                input_bits      = (i == 0) ? SEED_FRACTION_BITS :
                                  (correct_bits + GUARD_BITS < Y_BITS) ? correct_bits + GUARD_BITS : Y_BITS;
                correction_bits = work_bits - correct_bits + GUARD_BITS;
                if (correction_bits > Y_BITS) correction_bits = Y_BITS;
                if (correction_bits < 1)      correction_bits = 1;
                if (i == step)
                    plan = (field == 0) ? correct_bits : (field == 1) ? input_bits :
                           (field == 2) ? work_bits    : correction_bits;
                correct_bits = (2 * correct_bits - 1 < work_bits) ? 2 * correct_bits - 1 : work_bits;
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Seed table: y0 = 2 / (a + b) = 2^(k+2) / (2^(k+1) + 2*index + 1),
    // rounded to SEED_FRACTION_BITS fraction bits (k = SEED_BITS)
    //--------------------------------------------------------------------------
    function integer seed_value(input integer index);
        integer numerator, denominator;
        begin
            numerator   = 1 << (2 * SEED_BITS + 5);
            denominator = (1 << (SEED_BITS + 1)) + 2 * index + 1;
            seed_value  = (numerator + denominator / 2) / denominator;
        end
    endfunction

    wire [SEED_FRACTION_BITS+1:0] seed_table [0:(1 << SEED_BITS)-1];

    genvar entry;
    generate
        for (entry = 0; entry < (1 << SEED_BITS); entry = entry + 1) begin : seed_rom
            assign seed_table[entry] = seed_value(entry);
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Pipeline, step by step. Every y is kept with Y_BITS fraction bits
    // (padded with zeros), so all shifts below are by fixed, positive amounts.
    //--------------------------------------------------------------------------
    localparam STEP_CYCLES = 2 * MULTIPLY_STAGES;

    reg  [Y_BITS:0]    seed_y;
    reg  [D_BITS-1:0]  seed_divisor;
    reg  [TAG_WIDTH:0] seed_valid_and_tag = 0;   // powers up "not valid"

    always @(posedge clock) begin
        seed_y             <= seed_table[divisor[D_BITS-2 -: SEED_BITS]] << (Y_BITS - SEED_FRACTION_BITS);
        seed_divisor       <= divisor;
        seed_valid_and_tag <= {input_valid, input_tag};
    end

    wire [Y_BITS:0]    step_y            [0:ITERATIONS];
    wire [D_BITS-1:0]  step_divisor      [0:ITERATIONS];
    wire [TAG_WIDTH:0] step_valid_and_tag[0:ITERATIONS];

    assign step_y[0]             = seed_y;
    assign step_divisor[0]       = seed_divisor;
    assign step_valid_and_tag[0] = seed_valid_and_tag;

    genvar step;
    generate
        for (step = 0; step < ITERATIONS; step = step + 1) begin : newton_raphson_step
            localparam CORRECT_BITS    = plan(step, 0);
            localparam INPUT_BITS      = plan(step, 1);
            localparam WORK_BITS       = plan(step, 2);
            localparam CORRECTION_BITS = plan(step, 3);
            // d*y has D_BITS + INPUT_BITS fraction bits; e keeps WORK_BITS of them.
            // |e| < 2^-(CORRECT_BITS-2), so ERROR_WIDTH bits (with sign) hold it,
            // and only the low PRODUCT_LOW_BITS bits of d*y are needed (the
            // bits above cancel against the 1).
            localparam ERROR_SHIFT      = D_BITS + INPUT_BITS - WORK_BITS;
            localparam ERROR_WIDTH      = WORK_BITS - CORRECT_BITS + 3;
            localparam PRODUCT_LOW_BITS = ERROR_SHIFT + ERROR_WIDTH;

            // y truncated to INPUT_BITS (back on the Y_BITS grid)
            wire [Y_BITS:0] y_in = (step_y[step] >> (Y_BITS - INPUT_BITS)) << (Y_BITS - INPUT_BITS);

            // --- e = 1 - d * y ----------------------------------------------
            wire signed [ERROR_WIDTH-1:0] error;

            nr_multiply_add #(
                .A_WIDTH(D_BITS + 1), .B_WIDTH(INPUT_BITS + 2), .C_WIDTH(1),
                .SUM_WIDTH(PRODUCT_LOW_BITS), .RESULT_SHIFT(ERROR_SHIFT), .RESULT_WIDTH(ERROR_WIDTH),
                .SUBTRACT(1), .STAGES(MULTIPLY_STAGES)
            ) error_unit (
                .clock(clock),
                .a({1'b0, step_divisor[step]}),
                .b({1'b0, y_in[Y_BITS -: INPUT_BITS + 1]}),
                .c(1'b0),                        // the 1 cancels (only low bits kept)
                .result(error));

            // --- y_next = y + y * e -----------------------------------------
            wire [Y_BITS:0] y_delayed;

            nr_delay #(.WIDTH(Y_BITS + 1), .CYCLES(MULTIPLY_STAGES)) y_delay (
                .clock(clock), .in(y_in), .out(y_delayed));

            wire [CORRECTION_BITS:0] y_for_correction = y_delayed >> (Y_BITS - CORRECTION_BITS);
            wire [WORK_BITS:0]       y_for_sum        = y_delayed >> (Y_BITS - WORK_BITS);
            wire [WORK_BITS:0]       y_next;

            nr_multiply_add #(
                .A_WIDTH(CORRECTION_BITS + 2), .B_WIDTH(ERROR_WIDTH), .C_WIDTH(WORK_BITS + CORRECTION_BITS + 2),
                .SUM_WIDTH(WORK_BITS + CORRECTION_BITS + 3), .RESULT_SHIFT(CORRECTION_BITS),
                .RESULT_WIDTH(WORK_BITS + 1), .SUBTRACT(0), .STAGES(MULTIPLY_STAGES)
            ) update_unit (
                .clock(clock),
                .a({1'b0, y_for_correction}),
                .b(error),
                .c({1'b0, y_for_sum, {CORRECTION_BITS{1'b0}}}),
                .result(y_next));

            assign step_y[step + 1] = y_next << (Y_BITS - WORK_BITS);

            // --- divisor, valid and tag follow along ------------------------
            nr_delay #(.WIDTH(D_BITS), .CYCLES(STEP_CYCLES)) divisor_delay (
                .clock(clock), .in(step_divisor[step]), .out(step_divisor[step + 1]));
            nr_delay #(.WIDTH(TAG_WIDTH + 1), .CYCLES(STEP_CYCLES)) tag_delay (
                .clock(clock), .in(step_valid_and_tag[step]), .out(step_valid_and_tag[step + 1]));
        end
    endgenerate

    assign reciprocal                 = step_y[ITERATIONS];
    assign {output_valid, output_tag} = step_valid_and_tag[ITERATIONS];
endmodule

//==============================================================================
// nr_delay: WIDTH-bit signal delayed by CYCLES (>= 1) clock cycles
//==============================================================================
module nr_delay #(
    parameter WIDTH  = 1,
    parameter CYCLES = 1
)(
    input  wire             clock,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    reg [WIDTH-1:0] stage [0:CYCLES-1];
    integer i;

    // Power up at 0, so a delayed valid starts out "not valid"
    initial
        for (i = 0; i < CYCLES; i = i + 1)
            stage[i] = 0;

    always @(posedge clock) begin
        stage[0] <= in;
        for (i = 1; i < CYCLES; i = i + 1)
            stage[i] <= stage[i - 1];
    end

    assign out = stage[CYCLES-1];
endmodule
