`timescale 1ns / 1ps
//==============================================================================
// tb_dsp_profile
//
// Measures how many clock cycles each DSP operation takes at the synaptic
// module clock (12 MHz), and checks every result against the expected value.
//
// How cycles are counted:
//   1. The operands are applied between clock edges.
//   2. The next rising clock edge captures them. That is edge 1.
//   3. We keep counting edges until the module says its result is valid.
//   So "1 cycle" means the result is ready right after the next clock edge.
//
// Each test prints one line with the numbers and the cycle count, plus a
// PASS/FAIL line. The run ends with an overall PASS or FAIL.
//==============================================================================
module tb_dsp_profile;

    //--------------------------------------------------------------------------
    // Clock: 12 MHz, the Caravel clock that drives the synaptic module
    //--------------------------------------------------------------------------
    localparam real CLOCK_FREQUENCY_MHZ = 12.0;
    localparam real CLOCK_PERIOD_NS     = 1000.0 / CLOCK_FREQUENCY_MHZ;   // 83.333 ns

    reg clock = 0;
    always #(CLOCK_PERIOD_NS / 2.0) clock = ~clock;

    reg reset = 1;

    // Longest wait allowed before a test gives up: the slowest power example
    // (exponent 31) takes 2 + 30*18 = 542 cycles.
    localparam MAX_CYCLES_TO_WAIT = 600;

    //==========================================================================
    // Modules under test
    //==========================================================================

    // 1a. Addition, 18-bit Q2.16 (same format as the 18x18 multiply results)
    reg                add18_input_valid = 0;
    reg  signed [17:0] add18_operand_a, add18_operand_b;
    wire               add18_output_valid;
    wire signed [17:0] add18_result;

    dsp_adder #(.DATA_WIDTH(18)) adder_18bit (
        .clock(clock),
        .input_valid(add18_input_valid),
        .operand_a(add18_operand_a),
        .operand_b(add18_operand_b),
        .output_valid(add18_output_valid),
        .result(add18_result));

    // 1b. Addition, 32-bit Q16.16 (same word size as the current synaptic module)
    reg                add32_input_valid = 0;
    reg  signed [31:0] add32_operand_a, add32_operand_b;
    wire               add32_output_valid;
    wire signed [31:0] add32_result;

    dsp_adder #(.DATA_WIDTH(32)) adder_32bit (
        .clock(clock),
        .input_valid(add32_input_valid),
        .operand_a(add32_operand_a),
        .operand_b(add32_operand_b),
        .output_valid(add32_output_valid),
        .result(add32_result));

    // 2. 18x18 fixed-point multiply, Q2.16
    reg                mult18_input_valid = 0;
    reg  signed [17:0] mult18_operand_a, mult18_operand_b;
    wire               mult18_output_valid;
    wire signed [17:0] mult18_result;

    dsp_fixed_point_multiplier #(.DATA_WIDTH(18), .FRACTION_BITS(16)) multiplier_18x18 (
        .clock(clock),
        .input_valid(mult18_input_valid),
        .operand_a(mult18_operand_a),
        .operand_b(mult18_operand_b),
        .output_valid(mult18_output_valid),
        .result(mult18_result));

    // 3. 16x16 fixed-point multiply, Q4.12
    reg                mult16_input_valid = 0;
    reg  signed [15:0] mult16_operand_a, mult16_operand_b;
    wire               mult16_output_valid;
    wire signed [15:0] mult16_result;

    dsp_fixed_point_multiplier #(.DATA_WIDTH(16), .FRACTION_BITS(12)) multiplier_16x16 (
        .clock(clock),
        .input_valid(mult16_input_valid),
        .operand_a(mult16_operand_a),
        .operand_b(mult16_operand_b),
        .output_valid(mult16_output_valid),
        .result(mult16_result));

    // 4. base^exponent by shift-and-add, Q2.16
    reg                power_start = 0;
    reg  signed [17:0] power_base;
    reg  [4:0]         power_exponent;
    wire               power_busy, power_done;
    wire signed [17:0] power_result;

    shift_add_power #(.DATA_WIDTH(18), .FRACTION_BITS(16), .EXPONENT_WIDTH(5)) power_unit (
        .clock(clock),
        .reset(reset),
        .start(power_start),
        .base(power_base),
        .exponent(power_exponent),
        .busy(power_busy),
        .done(power_done),
        .result(power_result));

    //==========================================================================
    // Helpers
    //==========================================================================

    // Real number -> fixed point (integer with fraction_bits after the point)
    function integer to_fixed_point(input real value, input integer fraction_bits);
        to_fixed_point = $rtoi(value * (2.0 ** fraction_bits));
    endfunction

    // Fixed point -> real number, for printing
    function real to_real(input integer fixed_point_value, input integer fraction_bits);
        to_real = fixed_point_value / (2.0 ** fraction_bits);
    endfunction

    // Expected result of shift_add_power: same truncation, written as plain math
    function signed [17:0] expected_power_result(input signed [17:0] base, input integer exponent);
        reg [17:0] base_magnitude, running_power;
        reg [35:0] full_product;
        integer    multiply_number;
        begin
            base_magnitude = base[17] ? -base : base;
            running_power  = (exponent == 0) ? (18'd1 << 16) : base_magnitude;
            for (multiply_number = 1; multiply_number < exponent; multiply_number = multiply_number + 1) begin
                full_product  = running_power * base_magnitude;
                running_power = full_product[16 +: 18];
            end
            expected_power_result = (base[17] && exponent[0]) ? -running_power : running_power;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Checking and reporting
    //--------------------------------------------------------------------------
    integer failure_count         = 0;   // failed checks over the whole run
    integer check_count           = 0;   // checks performed over the whole run
    integer test_count            = 0;   // test_* calls so far
    integer failures_before_test  = 0;   // failure_count when the current test started

    // Record one check. A false condition is printed and counted as a failure.
    task check(input condition, input [8*48-1:0] description);
        begin
            check_count = check_count + 1;
            if (!condition) begin
                failure_count = failure_count + 1;
                $display("  CHECK FAILED: %0s at %0t ns", description, $time);
            end
        end
    endtask

    // Print PASS or FAIL for the test that just ran
    task report_test(input [8*40-1:0] test_name);
        begin
            test_count = test_count + 1;
            if (failure_count == failures_before_test)
                $display("PASS: test %0d - %0s", test_count, test_name);
            else
                $display("FAIL: test %0d - %0s", test_count, test_name);
        end
    endtask

    //==========================================================================
    // Tests. Each one: apply operands for one clock, count cycles until the
    // result is valid, check the value and the cycle count, print a line.
    //==========================================================================
    integer cycles;   // measured cycles for the current test

    task test_addition_18bit(input real value_a, input real value_b);
        reg signed [17:0] expected_sum;
        begin
            failures_before_test = failure_count;

            // Apply operands
            @(negedge clock);
            add18_operand_a   = to_fixed_point(value_a, 16);
            add18_operand_b   = to_fixed_point(value_b, 16);
            add18_input_valid = 1;
            expected_sum      = add18_operand_a + add18_operand_b;

            // Edge 1 captures the operands; then wait for the result
            @(posedge clock); #1 add18_input_valid = 0;
            cycles = 1;
            while (!add18_output_valid && cycles < MAX_CYCLES_TO_WAIT) begin
                @(posedge clock); #1 cycles = cycles + 1;
            end

            check(add18_result === expected_sum, "18-bit add: result == a + b");
            check(cycles == 1,                   "18-bit add: takes 1 cycle");
            report_test("18-bit addition");
            $display("  ADD  18-bit Q2.16   %9.5f + %9.5f = %9.5f   | %0d cycle",
                     to_real(add18_operand_a, 16), to_real(add18_operand_b, 16),
                     to_real(add18_result, 16), cycles);
        end
    endtask

    task test_addition_32bit(input real value_a, input real value_b);
        reg signed [31:0] expected_sum;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            add32_operand_a   = to_fixed_point(value_a, 16);
            add32_operand_b   = to_fixed_point(value_b, 16);
            add32_input_valid = 1;
            expected_sum      = add32_operand_a + add32_operand_b;

            @(posedge clock); #1 add32_input_valid = 0;
            cycles = 1;
            while (!add32_output_valid && cycles < MAX_CYCLES_TO_WAIT) begin
                @(posedge clock); #1 cycles = cycles + 1;
            end

            check(add32_result === expected_sum, "32-bit add: result == a + b");
            check(cycles == 1,                   "32-bit add: takes 1 cycle");
            report_test("32-bit addition");
            $display("  ADD  32-bit Q16.16 %10.4f + %10.4f = %10.4f | %0d cycle",
                     to_real(add32_operand_a, 16), to_real(add32_operand_b, 16),
                     to_real(add32_result, 16), cycles);
        end
    endtask

    task test_multiply_18bit(input real value_a, input real value_b);
        reg signed [35:0] full_product;
        reg signed [17:0] expected_product;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            mult18_operand_a   = to_fixed_point(value_a, 16);
            mult18_operand_b   = to_fixed_point(value_b, 16);
            mult18_input_valid = 1;
            full_product       = mult18_operand_a * mult18_operand_b;
            expected_product   = full_product[16 +: 18];   // back to Q2.16

            @(posedge clock); #1 mult18_input_valid = 0;
            cycles = 1;
            while (!mult18_output_valid && cycles < MAX_CYCLES_TO_WAIT) begin
                @(posedge clock); #1 cycles = cycles + 1;
            end

            check(mult18_result === expected_product, "18x18 multiply: result correct");
            check(cycles == 1,                        "18x18 multiply: takes 1 cycle");
            report_test("18x18 multiply");
            $display("  MULT 18x18 Q2.16   %8.5f x %8.5f = %9.5f (exact %9.5f) | %0d cycle",
                     to_real(mult18_operand_a, 16), to_real(mult18_operand_b, 16),
                     to_real(mult18_result, 16),
                     to_real(mult18_operand_a, 16) * to_real(mult18_operand_b, 16), cycles);
        end
    endtask

    task test_multiply_16bit(input real value_a, input real value_b);
        reg signed [31:0] full_product;
        reg signed [15:0] expected_product;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            mult16_operand_a   = to_fixed_point(value_a, 12);
            mult16_operand_b   = to_fixed_point(value_b, 12);
            mult16_input_valid = 1;
            full_product       = mult16_operand_a * mult16_operand_b;
            expected_product   = full_product[12 +: 16];   // back to Q4.12

            @(posedge clock); #1 mult16_input_valid = 0;
            cycles = 1;
            while (!mult16_output_valid && cycles < MAX_CYCLES_TO_WAIT) begin
                @(posedge clock); #1 cycles = cycles + 1;
            end

            check(mult16_result === expected_product, "16x16 multiply: result correct");
            check(cycles == 1,                        "16x16 multiply: takes 1 cycle");
            report_test("16x16 multiply");
            $display("  MULT 16x16 Q4.12   %8.4f x %8.4f = %9.4f (exact %9.4f) | %0d cycle",
                     to_real(mult16_operand_a, 12), to_real(mult16_operand_b, 12),
                     to_real(mult16_result, 12),
                     to_real(mult16_operand_a, 12) * to_real(mult16_operand_b, 12), cycles);
        end
    endtask

    task test_power(input real base_value, input integer exponent_value);
        reg signed [17:0] expected_power;
        integer           expected_cycles;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            power_base      = to_fixed_point(base_value, 16);
            power_exponent  = exponent_value;
            power_start     = 1;
            expected_power  = expected_power_result(power_base, exponent_value);
            expected_cycles = (exponent_value <= 1) ? 2 : 2 + (exponent_value - 1) * 18;

            @(posedge clock); #1 power_start = 0;
            cycles = 1;
            while (!power_done && cycles < MAX_CYCLES_TO_WAIT) begin
                @(posedge clock); #1 cycles = cycles + 1;
            end

            check(power_done === 1'b1,             "power: finished before timeout");
            check(power_result === expected_power, "power: result correct");
            check(cycles == expected_cycles,       "power: takes 2 + (exponent-1)*18 cycles");
            @(posedge clock); #1;
            check(power_done === 1'b0,             "power: done lasts one cycle");
            check(power_busy === 1'b0,             "power: busy low after done");
            report_test("shift-add power");
            $display("  POW  Q2.16  (%8.5f)^%0d = %9.5f (exact %9.5f) | %0d cycles = %0.1f ns",
                     to_real(power_base, 16), exponent_value, to_real(power_result, 16),
                     to_real(power_base, 16) ** exponent_value, cycles, cycles * CLOCK_PERIOD_NS);
        end
    endtask

    //==========================================================================
    // Test sequence
    //==========================================================================
    initial begin
        $display("Clock: %0.1f MHz (period %0.3f ns)", CLOCK_FREQUENCY_MHZ, CLOCK_PERIOD_NS);
        repeat (3) @(posedge clock);
        #1 reset = 0;

        $display("\n--- 1a. Addition, 18-bit Q2.16 (one DSP48E2 adder) ---");
        test_addition_18bit( 0.75,    0.5);
        test_addition_18bit(-1.25,    0.375);
        test_addition_18bit( 1.125,  -1.9);
        test_addition_18bit( 0.0001,  0.0002);

        $display("\n--- 1b. Addition, 32-bit Q16.16 (one DSP48E2 adder) ---");
        test_addition_32bit(  1.5,       2.25);
        test_addition_32bit( -3.75,      1.25);
        test_addition_32bit(100.5,      -0.125);
        test_addition_32bit( -0.000015, -1234.5);

        $display("\n--- 2. 18x18 fixed-point multiply, Q2.16 (one DSP48E2) ---");
        test_multiply_18bit( 1.5,   0.75);
        test_multiply_18bit(-1.25,  1.5);
        test_multiply_18bit( 0.1,   0.2);
        test_multiply_18bit(-0.5,  -0.5);

        $display("\n--- 3. 16x16 fixed-point multiply, Q4.12 (one DSP48E2) ---");
        test_multiply_16bit( 3.5,   2.25);
        test_multiply_16bit(-2.5,   1.75);
        test_multiply_16bit( 0.1,   0.2);
        test_multiply_16bit(-1.0,  -7.5);

        $display("\n--- 4. base^exponent by shift-and-add, Q2.16 ---");
        test_power( 0.75, 0);
        test_power( 0.75, 1);
        test_power( 1.25, 2);
        test_power(-1.2,  3);
        test_power( 0.9,  4);
        test_power( 1.1,  5);
        test_power( 0.5,  8);

        $display("\n%0d failed checks out of %0d", failure_count, check_count);
        if (failure_count == 0) $display("PASS: all %0d tests", test_count);
        else                    $display("FAIL: %0d failed checks", failure_count);
        $finish;
    end
endmodule
