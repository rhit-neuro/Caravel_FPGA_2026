`timescale 1ns / 1ps
//==============================================================================
// tb_dsp_profile
//
// Counts how many clock cycles each operation takes, for every pipeline
// option, and checks every answer.
//
// How cycles are counted:
//   1. Inputs are applied between clock edges (on the falling edge).
//   2. The next rising edge captures them. That is edge 1.
//   3. Count edges until the module's valid/done signal goes high.
//   "1 cycle" = the answer is ready right after the next clock edge.
//
// Cycle counts do not depend on the clock frequency. Whether a design can
// actually run at 100-600 MHz is decided by the Vivado builds, not here.
//==============================================================================
module tb_dsp_profile;

    //--------------------------------------------------------------------------
    // Clock (any frequency gives the same cycle counts)
    //--------------------------------------------------------------------------
    localparam real CLOCK_PERIOD_NS = 10.0;   // 100 MHz

    reg clock = 0;
    always #(CLOCK_PERIOD_NS / 2.0) clock = ~clock;

    reg reset = 1;

    localparam MAX_CYCLES_TO_WAIT = 600;   // slowest power example needs 542

    //==========================================================================
    // Modules under test
    //==========================================================================

    // 1. Addition, 18-bit Q2.16: 1 and 2 pipeline stages
    reg                add_input_valid = 0;
    reg  signed [17:0] add_operand_a, add_operand_b;
    wire [1:0]         add_output_valid;          // [0] = 1 stage, [1] = 2 stages
    wire signed [17:0] add_result [0:1];

    // 2. 18x18 multiply, Q2.16: 1 to 4 pipeline stages
    reg                mult18_input_valid = 0;
    reg  signed [17:0] mult18_operand_a, mult18_operand_b;
    wire [3:0]         mult18_output_valid;       // [n-1] = n stages
    wire signed [17:0] mult18_result [0:3];

    // 3. 16x16 multiply, Q4.12: 1 to 4 pipeline stages
    reg                mult16_input_valid = 0;
    reg  signed [15:0] mult16_operand_a, mult16_operand_b;
    wire [3:0]         mult16_output_valid;
    wire signed [15:0] mult16_result [0:3];

    // 5. BRAM, 1024 x 18: 1 and 2 read pipeline stages
    reg                bram_write_enable = 0;
    reg                bram_read_enable  = 0;
    reg  [9:0]         bram_address;
    reg  [17:0]        bram_write_data;
    wire [1:0]         bram_read_valid;
    wire [17:0]        bram_read_data [0:1];

    genvar stages;
    generate
        for (stages = 1; stages <= 2; stages = stages + 1) begin : adder
            dsp_adder #(.DATA_WIDTH(18), .PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .input_valid(add_input_valid),
                .operand_a(add_operand_a),
                .operand_b(add_operand_b),
                .output_valid(add_output_valid[stages-1]),
                .result(add_result[stages-1]));
        end

        for (stages = 1; stages <= 4; stages = stages + 1) begin : multiplier_18x18
            dsp_fixed_point_multiplier #(.DATA_WIDTH(18), .FRACTION_BITS(16), .PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .input_valid(mult18_input_valid),
                .operand_a(mult18_operand_a),
                .operand_b(mult18_operand_b),
                .output_valid(mult18_output_valid[stages-1]),
                .result(mult18_result[stages-1]));
        end

        for (stages = 1; stages <= 4; stages = stages + 1) begin : multiplier_16x16
            dsp_fixed_point_multiplier #(.DATA_WIDTH(16), .FRACTION_BITS(12), .PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .input_valid(mult16_input_valid),
                .operand_a(mult16_operand_a),
                .operand_b(mult16_operand_b),
                .output_valid(mult16_output_valid[stages-1]),
                .result(mult16_result[stages-1]));
        end

        for (stages = 1; stages <= 2; stages = stages + 1) begin : memory
            bram_memory #(.DATA_WIDTH(18), .ADDRESS_WIDTH(10), .READ_PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .write_enable(bram_write_enable),
                .write_address(bram_address),
                .write_data(bram_write_data),
                .read_enable(bram_read_enable),
                .read_address(bram_address),
                .read_valid(bram_read_valid[stages-1]),
                .read_data(bram_read_data[stages-1]));
        end
    endgenerate

    // 4. base^exponent by shift-and-add, Q2.16 (no pipeline options)
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
    integer failure_count        = 0;
    integer check_count          = 0;
    integer test_count           = 0;
    integer failures_before_test = 0;

    // Record one check; a false condition is printed and counted
    task check(input condition, input [8*48-1:0] description);
        begin
            check_count = check_count + 1;
            if (!condition) begin
                failure_count = failure_count + 1;
                $display("  CHECK FAILED: %0s at %0t ns", description, $time);
            end
        end
    endtask

    task report_test(input [8*40-1:0] test_name);
        begin
            test_count = test_count + 1;
            if (failure_count == failures_before_test)
                $display("PASS: test %0d - %0s", test_count, test_name);
            else
                $display("FAIL: test %0d - %0s", test_count, test_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Cycle counting for modules that have several pipeline options.
    // After edge 1, watch every option's valid signal for a few cycles and
    // record the cycle each one goes high.
    //--------------------------------------------------------------------------
    integer cycles_for_option [0:3];   // index = pipeline stages - 1
    integer option, cycle;

    task start_cycle_count;
        for (option = 0; option < 4; option = option + 1)
            cycles_for_option[option] = -1;   // -1 = not valid yet
    endtask

    //==========================================================================
    // Tests
    //==========================================================================

    task test_addition(input real value_a, input real value_b);
        reg signed [17:0] expected_sum;
        begin
            failures_before_test = failure_count;

            // Apply operands
            @(negedge clock);
            add_operand_a   = to_fixed_point(value_a, 16);
            add_operand_b   = to_fixed_point(value_b, 16);
            add_input_valid = 1;
            expected_sum    = add_operand_a + add_operand_b;
            start_cycle_count;

            // Edge 1 captures the operands; then watch both options
            @(posedge clock); #1 add_input_valid = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 2; option = option + 1)
                    if (add_output_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(add_result[option] === expected_sum, "add: result == a + b");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 2; option = option + 1)
                check(cycles_for_option[option] == option + 1, "add: cycles == pipeline stages");
            report_test("addition");
            $display("  ADD  Q2.16  %9.5f + %9.5f = %9.5f | stages 1/2: %0d/%0d cycles",
                     to_real(add_operand_a, 16), to_real(add_operand_b, 16), to_real(add_result[0], 16),
                     cycles_for_option[0], cycles_for_option[1]);
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
            start_cycle_count;

            @(posedge clock); #1 mult18_input_valid = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 4; option = option + 1)
                    if (mult18_output_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(mult18_result[option] === expected_product, "18x18 multiply: result correct");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 4; option = option + 1)
                check(cycles_for_option[option] == option + 1, "18x18 multiply: cycles == stages");
            report_test("18x18 multiply");
            $display("  MULT 18x18 Q2.16  %8.5f x %8.5f = %9.5f | stages 1/2/3/4: %0d/%0d/%0d/%0d cycles",
                     to_real(mult18_operand_a, 16), to_real(mult18_operand_b, 16), to_real(mult18_result[0], 16),
                     cycles_for_option[0], cycles_for_option[1], cycles_for_option[2], cycles_for_option[3]);
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
            start_cycle_count;

            @(posedge clock); #1 mult16_input_valid = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 4; option = option + 1)
                    if (mult16_output_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(mult16_result[option] === expected_product, "16x16 multiply: result correct");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 4; option = option + 1)
                check(cycles_for_option[option] == option + 1, "16x16 multiply: cycles == stages");
            report_test("16x16 multiply");
            $display("  MULT 16x16 Q4.12  %8.4f x %8.4f = %9.4f | stages 1/2/3/4: %0d/%0d/%0d/%0d cycles",
                     to_real(mult16_operand_a, 12), to_real(mult16_operand_b, 12), to_real(mult16_result[0], 12),
                     cycles_for_option[0], cycles_for_option[1], cycles_for_option[2], cycles_for_option[3]);
        end
    endtask

    task test_power(input real base_value, input integer exponent_value);
        reg signed [17:0] expected_power;
        integer           expected_cycles, cycles;
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
            report_test("shift-add power");
            $display("  POW  Q2.16  (%8.5f)^%0d = %9.5f | %0d cycles",
                     to_real(power_base, 16), exponent_value, to_real(power_result, 16), cycles);
        end
    endtask

    // Write a word, then read it back starting the very next cycle.
    // If the read returns the new word, the write took 1 cycle.
    task test_bram(input integer address, input real value);
        begin
            failures_before_test = failure_count;

            // Write: edge 1 stores the word
            @(negedge clock);
            bram_address      = address;
            bram_write_data   = to_fixed_point(value, 16);
            bram_write_enable = 1;
            @(posedge clock); #1 bram_write_enable = 0;

            // Read the same address on the next cycle; its edge is the new edge 1
            @(negedge clock);
            bram_read_enable = 1;
            start_cycle_count;
            @(posedge clock); #1 bram_read_enable = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 2; option = option + 1)
                    if (bram_read_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(bram_read_data[option] === bram_write_data, "BRAM: read returns written word");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 2; option = option + 1)
                check(cycles_for_option[option] == option + 1, "BRAM: read cycles == read stages");
            report_test("BRAM write + read");
            $display("  BRAM address %4d: wrote %9.5f, read %9.5f | write: 1 cycle, read stages 1/2: %0d/%0d cycles",
                     address, value, to_real($signed(bram_read_data[0]), 16),
                     cycles_for_option[0], cycles_for_option[1]);
        end
    endtask

    //==========================================================================
    // Test sequence
    //==========================================================================
    initial begin
        repeat (3) @(posedge clock);
        #1 reset = 0;

        $display("\n--- 1. Addition, 18-bit Q2.16 ---");
        test_addition( 0.75,  0.5);
        test_addition(-1.25,  0.375);
        test_addition( 1.125, -1.9);

        $display("\n--- 2. 18x18 fixed-point multiply, Q2.16 ---");
        test_multiply_18bit( 1.5,   0.75);
        test_multiply_18bit(-1.25,  1.5);
        test_multiply_18bit( 0.1,   0.2);

        $display("\n--- 3. 16x16 fixed-point multiply, Q4.12 ---");
        test_multiply_16bit( 3.5,  2.25);
        test_multiply_16bit(-2.5,  1.75);
        test_multiply_16bit(-1.0, -7.5);

        $display("\n--- 4. base^exponent by shift-and-add, Q2.16 ---");
        test_power( 0.75, 1);
        test_power( 1.25, 2);
        test_power(-1.2,  3);
        test_power( 1.1,  5);

        $display("\n--- 5. BRAM write then read, 1024 x 18 ---");
        test_bram(   0,  0.25);
        test_bram(   5,  1.5);
        test_bram(1023, -0.75);

        $display("\n%0d failed checks out of %0d", failure_count, check_count);
        if (failure_count == 0) $display("PASS: all %0d tests", test_count);
        else                    $display("FAIL: %0d failed checks", failure_count);
        $finish;
    end
endmodule
