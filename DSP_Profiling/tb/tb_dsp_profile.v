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

    // 6. URAM, 4096 x 72: 1, 2 and 3 read pipeline stages
    reg                uram_write_enable = 0;
    reg                uram_read_enable  = 0;
    reg  [11:0]        uram_address;
    reg  [71:0]        uram_write_data;
    wire [2:0]         uram_read_valid;
    wire [71:0]        uram_read_data [0:2];

    genvar stages;
    generate
        for (stages = 1; stages <= 3; stages = stages + 1) begin : ultra_memory
            uram_memory #(.DATA_WIDTH(72), .ADDRESS_WIDTH(12), .READ_PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .write_enable(uram_write_enable),
                .write_address(uram_address),
                .write_data(uram_write_data),
                .read_enable(uram_read_enable),
                .read_address(uram_address),
                .read_valid(uram_read_valid[stages-1]),
                .read_data(uram_read_data[stages-1]));
        end

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

    // 7. 32-bit Q16.16: add (1-2 stages), multiply (1-4 stages), power
    reg                add32_input_valid = 0;
    reg  signed [31:0] add32_operand_a, add32_operand_b;
    wire [1:0]         add32_output_valid;
    wire signed [31:0] add32_result [0:1];

    reg                mult32_input_valid = 0;
    reg  signed [31:0] mult32_operand_a, mult32_operand_b;
    wire [3:0]         mult32_output_valid;
    wire signed [31:0] mult32_result [0:3];

    generate
        for (stages = 1; stages <= 2; stages = stages + 1) begin : adder_32bit
            dsp_adder #(.DATA_WIDTH(32), .PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .input_valid(add32_input_valid),
                .operand_a(add32_operand_a),
                .operand_b(add32_operand_b),
                .output_valid(add32_output_valid[stages-1]),
                .result(add32_result[stages-1]));
        end

        for (stages = 1; stages <= 4; stages = stages + 1) begin : multiplier_32x32
            dsp_fixed_point_multiplier #(.DATA_WIDTH(32), .FRACTION_BITS(16), .PIPELINE_STAGES(stages)) unit (
                .clock(clock),
                .input_valid(mult32_input_valid),
                .operand_a(mult32_operand_a),
                .operand_b(mult32_operand_b),
                .output_valid(mult32_output_valid[stages-1]),
                .result(mult32_result[stages-1]));
        end
    endgenerate

    reg                power32_start = 0;
    reg  signed [31:0] power32_base;
    reg  [4:0]         power32_exponent;
    wire               power32_busy, power32_done;
    wire signed [31:0] power32_result;

    shift_add_power #(.DATA_WIDTH(32), .FRACTION_BITS(16), .EXPONENT_WIDTH(5)) power_unit_32bit (
        .clock(clock),
        .reset(reset),
        .start(power32_start),
        .base(power32_base),
        .exponent(power32_exponent),
        .busy(power32_busy),
        .done(power32_done),
        .result(power32_result));

    // 8. Division at 16-bit Q4.12, 18-bit Q2.16 and 32-bit Q16.16
    reg                divide_start = 0;
    reg  signed [15:0] divide16_dividend, divide16_divisor;
    reg  signed [17:0] divide18_dividend, divide18_divisor;
    reg  signed [31:0] divide32_dividend, divide32_divisor;
    wire [2:0]         divide_done;               // [0] = 16-bit, [1] = 18-bit, [2] = 32-bit
    wire signed [15:0] divide16_quotient;
    wire signed [17:0] divide18_quotient;
    wire signed [31:0] divide32_quotient;

    shift_subtract_divider #(.DATA_WIDTH(16), .FRACTION_BITS(12)) divider_16bit (
        .clock(clock), .reset(reset), .start(divide_start),
        .dividend(divide16_dividend), .divisor(divide16_divisor),
        .busy(), .done(divide_done[0]), .quotient(divide16_quotient), .divide_by_zero());

    shift_subtract_divider #(.DATA_WIDTH(18), .FRACTION_BITS(16)) divider_18bit (
        .clock(clock), .reset(reset), .start(divide_start),
        .dividend(divide18_dividend), .divisor(divide18_divisor),
        .busy(), .done(divide_done[1]), .quotient(divide18_quotient), .divide_by_zero());

    shift_subtract_divider #(.DATA_WIDTH(32), .FRACTION_BITS(16)) divider_32bit (
        .clock(clock), .reset(reset), .start(divide_start),
        .dividend(divide32_dividend), .divisor(divide32_divisor),
        .busy(), .done(divide_done[2]), .quotient(divide32_quotient), .divide_by_zero());

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

    // Same as expected_power_result, for 32-bit Q16.16
    function signed [31:0] expected_power_result_32bit(input signed [31:0] base, input integer exponent);
        reg [31:0] base_magnitude, running_power;
        reg [63:0] full_product;
        integer    multiply_number;
        begin
            base_magnitude = base[31] ? -base : base;
            running_power  = (exponent == 0) ? (32'd1 << 16) : base_magnitude;
            for (multiply_number = 1; multiply_number < exponent; multiply_number = multiply_number + 1) begin
                full_product  = running_power * base_magnitude;
                running_power = full_product[16 +: 32];
            end
            expected_power_result_32bit = (base[31] && exponent[0]) ? -running_power : running_power;
        end
    endfunction

    // Expected quotient: (|dividend| << fraction_bits) / |divisor|, truncated,
    // with the sign applied afterwards (same as shift_subtract_divider)
    function signed [31:0] expected_quotient(input signed [31:0] dividend, input signed [31:0] divisor,
                                             input integer fraction_bits);
        reg [63:0] dividend_magnitude, divisor_magnitude, quotient_magnitude;
        begin
            dividend_magnitude = (dividend < 0) ? -dividend : dividend;
            divisor_magnitude  = (divisor  < 0) ? -divisor  : divisor;
            quotient_magnitude = (dividend_magnitude << fraction_bits) / divisor_magnitude;
            expected_quotient  = ((dividend < 0) != (divisor < 0)) ? -quotient_magnitude : quotient_magnitude;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Checking and reporting
    //--------------------------------------------------------------------------
    integer failure_count        = 0;
    integer check_count          = 0;
    integer test_count           = 0;
    integer failed_test_count    = 0;
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
            else begin
                failed_test_count = failed_test_count + 1;
                $display("FAIL: test %0d - %0s", test_count, test_name);
            end
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

    // Same as test_bram, for the URAM (72-bit words, 3 read options)
    task test_uram(input integer address, input [71:0] value);
        begin
            failures_before_test = failure_count;

            // Write: edge 1 stores the word
            @(negedge clock);
            uram_address      = address;
            uram_write_data   = value;
            uram_write_enable = 1;
            @(posedge clock); #1 uram_write_enable = 0;

            // Read the same address on the next cycle
            @(negedge clock);
            uram_read_enable = 1;
            start_cycle_count;
            @(posedge clock); #1 uram_read_enable = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 3; option = option + 1)
                    if (uram_read_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(uram_read_data[option] === value, "URAM: read returns written word");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 3; option = option + 1)
                check(cycles_for_option[option] == option + 1, "URAM: read cycles == read stages");
            report_test("URAM write + read");
            $display("  URAM address %4d: wrote %h, read %h | write: 1 cycle, read stages 1/2/3: %0d/%0d/%0d cycles",
                     address, value, uram_read_data[0],
                     cycles_for_option[0], cycles_for_option[1], cycles_for_option[2]);
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
            start_cycle_count;

            @(posedge clock); #1 add32_input_valid = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 2; option = option + 1)
                    if (add32_output_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(add32_result[option] === expected_sum, "32-bit add: result == a + b");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 2; option = option + 1)
                check(cycles_for_option[option] == option + 1, "32-bit add: cycles == stages");
            report_test("32-bit addition");
            $display("  ADD  Q16.16  %11.4f + %11.4f = %11.4f | stages 1/2: %0d/%0d cycles",
                     to_real(add32_operand_a, 16), to_real(add32_operand_b, 16), to_real(add32_result[0], 16),
                     cycles_for_option[0], cycles_for_option[1]);
        end
    endtask

    task test_multiply_32bit(input real value_a, input real value_b);
        reg signed [63:0] full_product;
        reg signed [31:0] expected_product;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            mult32_operand_a   = to_fixed_point(value_a, 16);
            mult32_operand_b   = to_fixed_point(value_b, 16);
            mult32_input_valid = 1;
            full_product       = mult32_operand_a * mult32_operand_b;
            expected_product   = full_product[16 +: 32];   // back to Q16.16
            start_cycle_count;

            @(posedge clock); #1 mult32_input_valid = 0;
            for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
                for (option = 0; option < 4; option = option + 1)
                    if (mult32_output_valid[option] && cycles_for_option[option] < 0) begin
                        cycles_for_option[option] = cycle;
                        check(mult32_result[option] === expected_product, "32x32 multiply: result correct");
                    end
                @(posedge clock); #1;
            end

            for (option = 0; option < 4; option = option + 1)
                check(cycles_for_option[option] == option + 1, "32x32 multiply: cycles == stages");
            report_test("32x32 multiply");
            $display("  MULT 32x32 Q16.16  %10.4f x %10.4f = %11.4f | stages 1/2/3/4: %0d/%0d/%0d/%0d cycles",
                     to_real(mult32_operand_a, 16), to_real(mult32_operand_b, 16), to_real(mult32_result[0], 16),
                     cycles_for_option[0], cycles_for_option[1], cycles_for_option[2], cycles_for_option[3]);
        end
    endtask

    task test_power_32bit(input real base_value, input integer exponent_value);
        reg signed [31:0] expected_power;
        integer           expected_cycles, cycles;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            power32_base     = to_fixed_point(base_value, 16);
            power32_exponent = exponent_value;
            power32_start    = 1;
            expected_power   = expected_power_result_32bit(power32_base, exponent_value);
            expected_cycles  = (exponent_value <= 1) ? 2 : 2 + (exponent_value - 1) * 32;

            @(posedge clock); #1 power32_start = 0;
            cycles = 1;
            while (!power32_done && cycles < MAX_CYCLES_TO_WAIT * 2) begin
                @(posedge clock); #1 cycles = cycles + 1;
            end

            check(power32_done === 1'b1,             "32-bit power: finished before timeout");
            check(power32_result === expected_power, "32-bit power: result correct");
            check(cycles == expected_cycles,         "32-bit power: takes 2 + (exponent-1)*32 cycles");
            report_test("32-bit shift-add power");
            $display("  POW  Q16.16  (%9.4f)^%0d = %11.4f | %0d cycles",
                     to_real(power32_base, 16), exponent_value, to_real(power32_result, 16), cycles);
        end
    endtask

    // One division, sent to the 16-, 18- and 32-bit dividers at the same time
    task test_divide(input real value_a, input real value_b);
        reg signed [31:0] expected16, expected18, expected32;
        begin
            failures_before_test = failure_count;

            @(negedge clock);
            divide16_dividend = to_fixed_point(value_a, 12);  divide16_divisor = to_fixed_point(value_b, 12);
            divide18_dividend = to_fixed_point(value_a, 16);  divide18_divisor = to_fixed_point(value_b, 16);
            divide32_dividend = to_fixed_point(value_a, 16);  divide32_divisor = to_fixed_point(value_b, 16);
            expected16 = expected_quotient(divide16_dividend, divide16_divisor, 12);
            expected18 = expected_quotient(divide18_dividend, divide18_divisor, 16);
            expected32 = expected_quotient(divide32_dividend, divide32_divisor, 16);
            divide_start = 1;
            start_cycle_count;

            @(posedge clock); #1 divide_start = 0;
            for (cycle = 1; cycle <= 60; cycle = cycle + 1) begin
                for (option = 0; option < 3; option = option + 1)
                    if (divide_done[option] && cycles_for_option[option] < 0)
                        cycles_for_option[option] = cycle;
                @(posedge clock); #1;
            end

            check(divide16_quotient === expected16[15:0], "16-bit divide: result correct");
            check(divide18_quotient === expected18[17:0], "18-bit divide: result correct");
            check(divide32_quotient === expected32,       "32-bit divide: result correct");
            check(cycles_for_option[0] == 2 + 16 + 12, "16-bit divide: takes 30 cycles");
            check(cycles_for_option[1] == 2 + 18 + 16, "18-bit divide: takes 36 cycles");
            check(cycles_for_option[2] == 2 + 32 + 16, "32-bit divide: takes 50 cycles");
            report_test("division");
            $display("  DIV  %8.4f / %8.4f = %8.4f (Q4.12) %9.5f (Q2.16) %10.5f (Q16.16) | 16/18/32-bit: %0d/%0d/%0d cycles",
                     value_a, value_b, to_real(divide16_quotient, 12), to_real(divide18_quotient, 16),
                     to_real(divide32_quotient, 16), cycles_for_option[0], cycles_for_option[1], cycles_for_option[2]);
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

        $display("\n--- 6. URAM write then read, 4096 x 72 ---");
        test_uram(   0, 72'h00_0000_0000_0000_0001);
        test_uram( 100, 72'hA5_DEAD_BEEF_0123_4567);
        test_uram(4095, 72'hFF_FFFF_FFFF_FFFF_FFFF);

        $display("\n--- 7. 32-bit fixed point, Q16.16 ---");
        test_addition_32bit( 1.5,      2.25);
        test_addition_32bit(-3.75,     1.25);
        test_addition_32bit(100.5,    -1234.125);
        test_multiply_32bit( 1.5,      0.75);
        test_multiply_32bit(-12.25,    3.5);
        test_multiply_32bit( 100.0,   -0.01);
        test_power_32bit( 1.5,  2);
        test_power_32bit(-2.0,  3);
        test_power_32bit( 1.1,  5);

        $display("\n--- 8. Division (shift-subtract), 16/18/32-bit ---");
        // Inputs and results stay inside the Q2.16 range (-2 to +2)
        test_divide( 0.25,  0.5);
        test_divide(-1.5,   1.25);
        test_divide( 0.75, -1.25);
        test_divide( 0.5,   1.5);

        // Summary in a form Veritas recognizes as a counter, not a failure
        // (a line like "0 failed checks" would be read as a FAIL marker)
        $display("\n%0d checks run", check_count);
        $display("Tests: %0d passed, %0d failed", test_count - failed_test_count, failed_test_count);
        if (failure_count == 0) $display("PASS: all %0d tests", test_count);
        else                    $display("FAIL: %0d checks did not hold", failure_count);
        $finish;
    end
endmodule
