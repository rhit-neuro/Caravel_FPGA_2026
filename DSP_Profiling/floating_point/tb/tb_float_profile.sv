`timescale 1ns / 1ps
//==============================================================================
// tb_float_profile
//
// Counts the clock cycles of ONE floating-point unit and checks its answers.
// run_float_simulation.tcl runs it once per configuration, setting:
//   OPERATION_CODE   0 = IP add, 1 = IP multiply, 2 = IP divide,
//                    3 = power x^n (IP multiplier),
//                    4 = current design add, 5 = current design multiply,
//                    6 = current design multiply-add (a*b + c)
//   DATA_WIDTH_VALUE 16 (IEEE half) or 32 (IEEE single)
//   LATENCY_VALUE    the IP's pipeline stages (1 for the current design)
//
// Cycles are counted as before: inputs applied, edge 1 captures them, count
// edges until output_valid / done. Answers are compared with the exact
// real-number result; floats can't hold that exactly, so a small relative
// error (set by the precision) is allowed.
//==============================================================================
module tb_float_profile;

    localparam OPERATION  = `OPERATION_CODE;
    localparam DATA_WIDTH = `DATA_WIDTH_VALUE;
    localparam LATENCY    = `LATENCY_VALUE;

    // Half: 5 exponent bits, 10 mantissa bits.  Single: 8 and 23.
    localparam EXPONENT_BITS = (DATA_WIDTH == 16) ? 5 : 8;
    localparam MANTISSA_BITS = (DATA_WIDTH == 16) ? 10 : 23;
    localparam EXPONENT_BIAS = (1 << (EXPONENT_BITS - 1)) - 1;

    reg clock = 0;
    always #5 clock = ~clock;
    reg reset = 1;

    //--------------------------------------------------------------------------
    // Unit under test
    //--------------------------------------------------------------------------
    reg                   input_valid = 0;
    reg  [DATA_WIDTH-1:0] operand_a, operand_b, operand_c;
    wire                  output_valid;
    wire [DATA_WIDTH-1:0] result;

    generate
        if (OPERATION <= 2) begin : ip_operation
            float_ip_unit #(.DATA_WIDTH(DATA_WIDTH)) unit (
                .clock(clock), .input_valid(input_valid),
                .operand_a(operand_a), .operand_b(operand_b),
                .output_valid(output_valid), .result(result));
        end else if (OPERATION == 3) begin : power
            float_power #(.DATA_WIDTH(DATA_WIDTH), .EXPONENT_WIDTH(5)) unit (
                .clock(clock), .reset(reset), .start(input_valid),
                .base(operand_a), .exponent(operand_b[4:0]),
                .busy(), .done(output_valid), .result(result));
        end else begin : current_design
            current_design_float_unit #(.OPERATION(OPERATION - 4)) unit (
                .clock(clock), .input_valid(input_valid),
                .operand_a(operand_a), .operand_b(operand_b), .operand_c(operand_c),
                .output_valid(output_valid), .result(result));
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Real number <-> float bits (normal numbers and zero; enough for testing)
    //--------------------------------------------------------------------------
    function automatic [DATA_WIDTH-1:0] to_float(input real value);
        real    magnitude;
        integer exponent;
        longint mantissa;
        begin
            if (value == 0.0) return 0;
            magnitude = (value < 0) ? -value : value;
            exponent  = 0;
            while (magnitude >= 2.0) begin magnitude = magnitude / 2.0; exponent++; end
            while (magnitude <  1.0) begin magnitude = magnitude * 2.0; exponent--; end
            // magnitude is now 1.xxx; keep MANTISSA_BITS fraction bits
            // (the longint'() cast already rounds to the nearest integer)
            mantissa = longint'((magnitude - 1.0) * (2.0 ** MANTISSA_BITS));
            if (mantissa == (1 << MANTISSA_BITS)) begin mantissa = 0; exponent++; end
            return {(value < 0) ? 1'b1 : 1'b0, EXPONENT_BITS'(exponent + EXPONENT_BIAS), MANTISSA_BITS'(mantissa)};
        end
    endfunction

    function automatic real to_real(input [DATA_WIDTH-1:0] bits);
        integer exponent_field;
        real    fraction;
        begin
            exponent_field = bits[DATA_WIDTH-2 -: EXPONENT_BITS];
            fraction       = bits[MANTISSA_BITS-1:0] / (2.0 ** MANTISSA_BITS);
            if (exponent_field == 0)   // zero or subnormal
                to_real = fraction * (2.0 ** (1 - EXPONENT_BIAS));
            else
                to_real = (1.0 + fraction) * (2.0 ** (exponent_field - EXPONENT_BIAS));
            if (bits[DATA_WIDTH-1]) to_real = -to_real;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Checking
    //--------------------------------------------------------------------------
    integer failure_count = 0, test_count = 0, failed_test_count = 0;
    integer cycles;

    // One float step is 2^-MANTISSA_BITS relative; allow `steps` of them
    function automatic bit close_enough(input real got, input real exact, input real steps);
        real allowed = steps * (2.0 ** -MANTISSA_BITS) * ((exact < 0) ? -exact : exact);
        real error   = got - exact;
        if (error < 0) error = -error;
        return error <= allowed;
    endfunction

    task automatic run_one(input real a, input real b, input real c, input real exact,
                           input real allowed_steps, input integer expected_cycles, input string label);
        begin
            test_count++;
            @(negedge clock);
            operand_a   = to_float(a);
            operand_b   = (OPERATION == 3) ? DATA_WIDTH'($rtoi(b)) : to_float(b);   // power: b = n
            operand_c   = to_float(c);
            input_valid = 1;

            @(posedge clock); #1 input_valid = 0;               // edge 1 captured the inputs
            cycles = 1;
            while (!output_valid && cycles < 1000) begin
                @(posedge clock); #1 cycles++;
            end

            if (close_enough(to_real(result), exact, allowed_steps) && cycles == expected_cycles)
                $display("PASS: %s = %g (exact %g) | %0d cycles", label, to_real(result), exact, cycles);
            else begin
                failed_test_count++;
                $display("FAIL: %s = %g (exact %g) | %0d cycles, expected %0d",
                         label, to_real(result), exact, cycles, expected_cycles);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Tests
    //--------------------------------------------------------------------------
    // Values every format can hold (half precision goes up to 65504)
    real a_values [4] = '{1.5, -3.75, 0.1, 1000.0};
    real b_values [4] = '{2.25, 0.5, 0.2, -0.25};
    real c_values [4] = '{0.5, 10.0, -0.02, 1.0};
    integer test, n;
    real a, b, c, exact;

    initial begin
        repeat (3) @(posedge clock);
        #1 reset = 0;

        for (test = 0; test < 4; test++) begin
            // The values exactly as this float format stores them (0.1 isn't exact)
            a = to_real(to_float(a_values[test]));
            b = to_real(to_float(b_values[test]));
            c = to_real(to_float(c_values[test]));

            case (OPERATION)
                0, 4: run_one(a, b, 0, a + b, 1, LATENCY, $sformatf("%g + %g", a, b));
                1, 5: run_one(a, b, 0, a * b, 1, LATENCY, $sformatf("%g * %g", a, b));
                2:    run_one(a, b, 0, a / b, 1, LATENCY, $sformatf("%g / %g", a, b));
                // The MAC rounds the product before adding (not fused), so the
                // expected answer uses the rounded product too
                6:    run_one(a, b, c, to_real(to_float(a * b)) + c, 1, LATENCY, $sformatf("%g * %g + %g", a, b, c));
                3: begin
                    // x^n with n = 2, 3, 5, 8; each multiply rounds, so allow n steps
                    n     = (test == 0) ? 2 : (test == 1) ? 3 : (test == 2) ? 5 : 8;
                    a     = to_real(to_float(1.1));
                    exact = a ** n;
                    run_one(a, n, 0, exact, n, 2 + (n - 1) * (LATENCY + 2), $sformatf("1.1 ^ %0d", n));
                end
            endcase
        end

        $display("Tests: %0d passed, %0d failed", test_count - failed_test_count, failed_test_count);
        $finish;
    end
endmodule
