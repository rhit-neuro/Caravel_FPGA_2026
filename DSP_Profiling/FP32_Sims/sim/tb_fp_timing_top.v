`timescale 1ns/1ps
// =============================================================================
// tb_fp_timing_top.v  --  testbench for fp_timing_top                  (v2)
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// A testbench is a Verilog program that never becomes hardware. It plays
// the role of the outside world: makes a clock, feeds inputs, and checks
// outputs.
//
// The same file runs in two modes:
//   1. RTL simulation (Vivado "Run Simulation", or Icarus). No gate delays;
//      checks the logic and measures latency in cycles.
//   2. TIMING simulation of the routed design for one clock frequency
//      (scripts/run_timing_sweep.tcl does this). Real gate + wire delays
//      from Vivado's SDF file; checks whether answers are still right at
//      that clock speed.
//
// WHAT IS MEASURED AND CHECKED (follows the 10/21 report's suggestions)
//   * Latency is MEASURED, not assumed: each input's acceptance cycle is
//     recorded, and latency = cycle its answer appears - acceptance cycle.
//     "Accepted" = the clock edge where in_valid=1 is captured (our units
//     never stall, so every in_valid=1 cycle is accepted).
//   * Every answer is matched to its own input (answers come out in order:
//     the n-th answer belongs to the n-th input) and checked against an
//     independent reference (C-style double math rounded to float).
//   * Counted per unit: correct, wrong, X (unknown value), missing (input
//     never answered), extra (answer with no input), latency min/max.
//   * Isolated operations first (one in flight, wait for the answer), then
//     continuous traffic (a new input every cycle).
//
// PASS RULES
//   add, multiply, shift : bit-for-bit equal to the correctly rounded float
//                          (round to nearest even; subnormals flushed to 0;
//                          any NaN matches any NaN)
//   exp                  : within 1 ulp (one step in the last bit) of the
//                          correctly rounded float
//   BRAM / URAM          : read data equals what was written
//   DDR4                 : data equals the fake model's answer (address)
//   every unit           : no X, no missing/extra answers, constant latency
//
// WHEN TO DRIVE AND WHEN TO READ PINS (why 'vclk' exists)
//   With real delays, the chip's registers see the clock a bit after the
//   clk pin toggles, and outputs change a bit after that. If the testbench
//   changed inputs exactly at the clk edge, it could race the chip.
//   So the testbench measures how late the outputs change after a clk edge
//   (using the 'heartbeat' pin, which flips every cycle), and builds 'vclk':
//   a copy of clk shifted by that delay + 10% of a period. Then:
//     rising  edge of vclk -> testbench changes inputs (like a neighbouring
//                             register on the same clock would)
//     falling edge of vclk -> testbench reads outputs (middle of the time
//                             the outputs are stable)
//   In RTL simulation the delay is 0, so vclk is just clk shifted by 10%.
//
// SETTINGS (can be changed from the command line with -d NAME=value):
//   CLK_PS    clock period in picoseconds (default 10000 = 100 MHz)
//   N_RANDOM  number of random back-to-back problems (default 20000)
//
// Testbench-only syntax used below:
//   initial begin ... end  runs once at time 0, top to bottom, like main()
//   #5                     wait 5 ns
//   @(posedge clk)         wait for the next rising clock edge
//   task                   like a C void function that can wait for time
//   $display(...)          printf      $random  rand()      real  double
//   === / !==              compare including X (unknown) bits exactly
// =============================================================================
`ifndef CLK_PS
  `define CLK_PS 10000
`endif
`ifndef N_RANDOM
  `define N_RANDOM 20000
`endif

module tb_fp_timing_top;

    // ------------------------------------------------------------- settings
    localparam integer HALF_PS  = `CLK_PS / 2;          // half period, whole ps
    localparam real    CLK_NS   = 2 * HALF_PS / 1000.0; // period actually used
    localparam N_DIR            = 20;                   // hand-picked cases
    localparam N_RANDOM         = `N_RANDOM;
    localparam N_TOTAL          = 2 * N_DIR + N_RANDOM; // directed twice + random
    localparam BOUNDARY_CYCLES  = 2;    // input + output registers in fp_timing_top
    localparam NM               = 32;   // memory words written/read
    localparam DDR_LATENCY      = 40;   // fake DDR delay (cycles) in the model
    localparam EXP_ULP_LIMIT    = 1;

    // ------------------------------------------------------------- clocks
    reg clk = 1'b0;
    always #(HALF_PS / 1000.0) clk = ~clk;   // the chip's clock

    real offset_ns = 0.1 * CLK_NS;           // vclk delay; updated after measuring
    reg  vclk = 1'b0;
    always @(clk) vclk <= #(offset_ns) clk;  // vclk = clk delayed by offset_ns

    integer vcyc = 0;     // testbench cycle counter (counts vclk cycles)
    reg checking = 1'b0;  // 1 once reset is done and outputs should be valid

    // ------------------------------------------------------------- DUT pins
    reg         rst = 1'b1;
    wire        heartbeat;
    reg         add_in_valid = 0, mul_in_valid = 0, shift_in_valid = 0, exp_in_valid = 0;
    reg  [31:0] add_a = 0, add_b = 0, mul_a = 0, mul_b = 0, shift_a = 0, exp_a = 0;
    reg  signed [8:0] shift_k = 0;
    wire        add_out_valid, mul_out_valid, shift_out_valid, exp_out_valid;
    wire [31:0] add_y, mul_y, shift_y, exp_y;

    reg         bram_we = 0, bram_re = 0, uram_we = 0, uram_re = 0;
    reg  [9:0]  bram_addr = 0;
    reg  [11:0] uram_addr = 0;
    reg  [31:0] bram_wdata = 0, uram_wdata = 0;
    wire        bram_rvalid, uram_rvalid;
    wire [31:0] bram_rdata, uram_rdata;

    reg          ddr_start = 0;
    reg  [39:0]  ddr_addr = 0;
    wire         ddr_done;
    wire [127:0] ddr_rdata;
    wire [15:0]  ddr_latency_cycles;
    wire [39:0]  m_axi_araddr;  wire [7:0] m_axi_arlen;  wire [2:0] m_axi_arsize;
    wire [1:0]   m_axi_arburst;
    wire         m_axi_arvalid, m_axi_arready, m_axi_rlast, m_axi_rvalid, m_axi_rready;
    wire [127:0] m_axi_rdata;   wire [1:0] m_axi_rresp;

    fp_timing_top dut (
        .clk(clk), .rst(rst), .heartbeat(heartbeat),
        .add_in_valid(add_in_valid), .add_a(add_a), .add_b(add_b),
        .add_out_valid(add_out_valid), .add_y(add_y),
        .mul_in_valid(mul_in_valid), .mul_a(mul_a), .mul_b(mul_b),
        .mul_out_valid(mul_out_valid), .mul_y(mul_y),
        .shift_in_valid(shift_in_valid), .shift_a(shift_a), .shift_k(shift_k),
        .shift_out_valid(shift_out_valid), .shift_y(shift_y),
        .exp_in_valid(exp_in_valid), .exp_a(exp_a),
        .exp_out_valid(exp_out_valid), .exp_y(exp_y),
        .bram_we(bram_we), .bram_re(bram_re), .bram_addr(bram_addr), .bram_wdata(bram_wdata),
        .bram_rvalid(bram_rvalid), .bram_rdata(bram_rdata),
        .uram_we(uram_we), .uram_re(uram_re), .uram_addr(uram_addr), .uram_wdata(uram_wdata),
        .uram_rvalid(uram_rvalid), .uram_rdata(uram_rdata),
        .ddr_start(ddr_start), .ddr_addr(ddr_addr), .ddr_done(ddr_done),
        .ddr_rdata(ddr_rdata), .ddr_latency_cycles(ddr_latency_cycles),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    // Fake PS + DDR4 (sim/axi_mem_model.v). It runs on vclk like the rest of
    // the testbench, and sees the DUT's AXI outputs as sampled on vclk's
    // falling edge (the safe reading time).
    reg        arvalid_s = 0, rready_s = 0;
    reg [39:0] araddr_s  = 0;
    always @(negedge vclk) begin
        arvalid_s <= (m_axi_arvalid === 1'b1);
        rready_s  <= (m_axi_rready  === 1'b1);
        araddr_s  <= m_axi_araddr;
    end
    axi_mem_model #(.LATENCY(DDR_LATENCY)) ddr_model (
        .clk(vclk), .rst(rst),
        .araddr(araddr_s), .arvalid(arvalid_s), .arready(m_axi_arready),
        .rdata(m_axi_rdata), .rresp(m_axi_rresp), .rlast(m_axi_rlast),
        .rvalid(m_axi_rvalid), .rready(rready_s)
    );

    // ------------------------------------------------------------- float helpers
    // float bits -> real (double). Builds the double's bit pattern by hand.
    function real f2r(input [31:0] f);
        reg [63:0] d;
        begin
            if (f[30:23] == 8'd0)        d = {f[31], 63'd0};                         // zero
            else if (f[30:23] == 8'hff)  d = {f[31], 11'h7ff, f[22:0], 29'd0};       // inf/NaN
            else d = {f[31], f[30:23] - 8'd127 + 11'd1023, f[22:0], 29'd0};          // normal
            f2r = $bitstoreal(d);
        end
    endfunction

    // real (double) -> float bits, rounding to nearest-even like the hardware.
    // This is the independent "correct answer" generator.
    function [31:0] r2f(input real r);
        reg [63:0] d;  integer e;  reg [24:0] m;  reg g, st;
        begin
            d = $realtobits(r);
            if (d[62:52] == 11'h7ff)     r2f = (d[51:0] != 0) ? 32'h7fc00000 : {d[63], 8'hff, 23'd0};
            else if (d[62:52] == 11'd0)  r2f = {d[63], 31'd0};
            else begin
                e  = d[62:52] - 1023 + 127;        // re-bias the exponent
                m  = {2'b01, d[51:29]};            // keep 24 mantissa bits
                g  = d[28];                        // guard bit
                st = |d[27:0];                     // sticky bit
                if (g && (st || m[0])) m = m + 1;  // round to nearest-even
                if (m[24]) begin m = m >> 1; e = e + 1; end
                if (e >= 255)    r2f = {d[63], 8'hff, 23'd0};
                else if (e <= 0) r2f = {d[63], 31'd0};
                else             r2f = {d[63], e[7:0], m[22:0]};
            end
        end
    endfunction

    function [31:0] random_float(input integer emin, input integer emax);
        reg [31:0] r;  integer e;
        begin
            r = $random;
            e = emin + ({$random} % (emax - emin + 1));
            random_float = {r[31], e[7:0], r[22:0]};
        end
    endfunction

    function is_nan(input [31:0] f);
        is_nan = (f[30:23] == 8'hff) && (f[22:0] != 0);
    endfunction

    function has_x(input [127:0] v);       // 1 if any bit is X or Z
        has_x = (^v === 1'bx);
    endfunction

    // exact match (any NaN equals any NaN)
    function same_float(input [31:0] p, input [31:0] q);
        same_float = (p === q) || (is_nan(p) && is_nan(q));
    endfunction

    // distance in ulps (steps of the last bit); used for exp
    function integer ulp_diff(input [31:0] p, input [31:0] q);
        begin
            if (same_float(p, q))      ulp_diff = 0;
            else if (p[31] != q[31])   ulp_diff = 32'h7fffffff;
            else ulp_diff = (p[30:0] > q[30:0]) ? p[30:0] - q[30:0] : q[30:0] - p[30:0];
        end
    endfunction

    // reference answers
    function [31:0] ref_add(input [31:0] a, input [31:0] b);
        begin
            if (is_nan(a) || is_nan(b) ||
                (a[30:0] == 31'h7f800000 && b[30:0] == 31'h7f800000 && a[31] != b[31]))
                ref_add = 32'h7fc00000;
            else
                ref_add = r2f(f2r(a) + f2r(b));
        end
    endfunction

    function [31:0] ref_mul(input [31:0] a, input [31:0] b);
        begin
            if (is_nan(a) || is_nan(b) ||
                (a[30:23] == 8'hff && b[30:23] == 0) || (b[30:23] == 8'hff && a[30:23] == 0))
                ref_mul = 32'h7fc00000;
            else
                ref_mul = r2f(f2r(a) * f2r(b));
        end
    endfunction

    function [31:0] ref_shift(input [31:0] a, input integer k);
        ref_shift = (a[30:23] == 8'hff) ? a : r2f(f2r(a) * (2.0 ** k));
    endfunction

    function [31:0] ref_exp(input [31:0] x);
        begin
            if (is_nan(x))              ref_exp = 32'h7fc00000;
            else if (x == 32'h7f800000) ref_exp = 32'h7f800000;   // e^inf  = inf
            else if (x == 32'hff800000) ref_exp = 32'h00000000;   // e^-inf = 0
            else                        ref_exp = r2f($exp(f2r(x)));
        end
    endfunction

    // ------------------------------------------------------------- test data
    reg  [31:0] A [0:N_TOTAL-1];          // like float A[N_TOTAL] in C
    reg  [31:0] B [0:N_TOTAL-1];
    reg  [31:0] X [0:N_TOTAL-1];          // inputs for exp
    reg  signed [8:0] K [0:N_TOTAL-1];    // shift amounts
    integer acc_cyc [0:N_TOTAL-1];        // cycle each math input was accepted
    integer i, j;

    initial begin
        // Directed cases: a/b for add & mul, x for exp
        A[0]=32'hbdcccccd; B[0]=32'h00000000; X[0]=32'h00000000; // -0.1 + 0  (old adder got this wrong), e^0
        A[1]=32'h3dcccccd; B[1]=32'h80000000; X[1]=32'h3f800000; // 0.1 + -0,  e^1
        A[2]=32'hbdcccccd; B[2]=32'h20000000; X[2]=32'hbf800000; // -0.1 + tiny, e^-1
        A[3]=32'h4b800000; B[3]=32'h40400000; X[3]=32'h42b17218; // 16777216 + 3, e^88.72 (just overflows)
        A[4]=32'h3f800000; B[4]=32'hbf800000; X[4]=32'h42b20000; // 1 - 1 = 0, e^89 = inf
        A[5]=32'h3f800001; B[5]=32'hbf800000; X[5]=32'hc2ae0000; // cancellation, e^-87
        A[6]=32'h7f7fffff; B[6]=32'h7f7fffff; X[6]=32'hc2c80000; // max+max = inf, e^-100 = 0
        A[7]=32'h7f800000; B[7]=32'hff800000; X[7]=32'h7fc00000; // inf - inf = NaN, e^NaN
        A[8]=32'h7f800000; B[8]=32'h3f800000; X[8]=32'h7f800000; // inf + 1, e^inf
        A[9]=32'h00000000; B[9]=32'h7f800000; X[9]=32'hff800000; // 0 * inf = NaN, e^-inf = 0
        A[10]=32'h3f000000; B[10]=32'h3e4ccccd; X[10]=32'h3e4ccccd; // 0.5 and 0.2, e^0.2
        A[11]=32'h3eb33333; B[11]=32'h3f000000; X[11]=32'h3727c5ac; // e^0.00001
        A[12]=32'h40490fdb; B[12]=32'hc0490fdb; X[12]=32'h40a00000; // pi - pi, e^5
        A[13]=32'h3f7fffff; B[13]=32'h33800000; X[13]=32'hc1200000; // rounding carry, e^-10
        A[14]=32'h1f800000; B[14]=32'h1f800000; X[14]=32'h3a83126f; // mul too small, e^0.001
        A[15]=32'hc2840000; B[15]=32'h3dcccccd; X[15]=32'hc0490fdb; // -66 + 0.1, e^-pi
        A[16]=32'h3fffffff; B[16]=32'h3fffffff; X[16]=32'h3f317218; // 1.9999999 x2 (long carry), e^ln2 = 2
        A[17]=32'h4b7fffff; B[17]=32'h3f800000; X[17]=32'h41a00000; // 16777215 + 1 (carry chain), e^20
        A[18]=32'h00800000; B[18]=32'h80800000; X[18]=32'h42b00000; // smallest normal - itself, e^88
        A[19]=32'h3f800000; B[19]=32'hb3800000; X[19]=32'hbf317218; // 1 - 2^-24 (renormalize), e^-ln2 = 0.5
        for (i = 0; i < N_DIR; i = i + 1) K[i] = (i * 37) % 64 - 32;
        K[6] = 9'sd100;  K[14] = -9'sd70;  // force a shift overflow and underflow

        // Stream part 1: the directed cases again, back to back
        for (i = 0; i < N_DIR; i = i + 1) begin
            A[N_DIR+i] = A[i]; B[N_DIR+i] = B[i]; X[N_DIR+i] = X[i]; K[N_DIR+i] = K[i];
        end
        // Stream part 2: random cases
        for (i = 2*N_DIR; i < N_TOTAL; i = i + 1) begin
            A[i] = random_float(64, 190);
            if (i % 2) B[i] = random_float(64, 190);
            else       B[i] = {~A[i][31], A[i][30:23], A[i][22:0] ^ ($random & 23'h00ffff)};
                       // ^ every other B is close to -A, to test cancellation
            X[i] = random_float(97, 133);    // |x| from about 1e-9 to 255
            K[i] = $random % 120;
        end
    end

    // memory test data
    reg  [9:0]  baddr [0:NM-1];
    reg  [11:0] uaddr [0:NM-1];
    reg  [31:0] bdata [0:NM-1];
    reg  [31:0] udata [0:NM-1];
    integer rd_entry [0:4*NM-1];   // which word each read asked for
    integer rd_cyc   [0:4*NM-1];   // cycle each read was accepted
    integer n_rd = 0;              // reads issued

    initial begin
        for (j = 0; j < NM; j = j + 1) begin
            baddr[j] = (j * 37 + 5) % 1024;      // scattered addresses
            uaddr[j] = (j * 251 + 9) % 4096;
            bdata[j] = $random;
            udata[j] = $random;
        end
    end

    // DDR test data
    reg [39:0] ddr_req_addr [0:2];
    integer    ddr_req_cyc  [0:2];
    initial begin
        ddr_req_addr[0] = 40'h00_1234_5670;
        ddr_req_addr[1] = 40'h00_0000_0040;
        ddr_req_addr[2] = 40'h07_ffff_fff0;
    end

    // ------------------------------------------------------------- score keeping
    // One set of counters per unit: index 0=add 1=mul 2=shift 3=exp 4=bram 5=uram 6=ddr4
    integer n_sent [0:6];     // inputs accepted
    integer n_out  [0:6];     // answers seen
    integer n_ok   [0:6];
    integer n_bad  [0:6];
    integer n_x    [0:6];
    integer n_extra[0:6];
    integer lat_min[0:6];
    integer lat_max[0:6];
    integer exp_worst_ulp = 0;
    integer ddr_reported = 0;
    integer u;

    initial begin
        for (u = 0; u < 7; u = u + 1) begin
            n_sent[u] = 0; n_out[u] = 0; n_ok[u] = 0; n_bad[u] = 0;
            n_x[u] = 0; n_extra[u] = 0; lat_min[u] = 999999; lat_max[u] = -1;
        end
    end

    // record one answer for unit 'unit': pass/fail, X flag, and its latency
    task score(input integer unit, input integer accepted_cyc, input pass, input xflag);
        integer lat;
        begin
            lat = vcyc - accepted_cyc - BOUNDARY_CYCLES;   // the unit's own latency
            if (lat < lat_min[unit]) lat_min[unit] = lat;
            if (lat > lat_max[unit]) lat_max[unit] = lat;
            if (xflag)      n_x[unit]   = n_x[unit] + 1;
            else if (pass)  n_ok[unit]  = n_ok[unit] + 1;
            else            n_bad[unit] = n_bad[unit] + 1;
            n_out[unit] = n_out[unit] + 1;
        end
    endtask

    // ------------------------------------------------------------- checker
    // Runs on every falling edge of vclk: the safe time to read outputs.
    reg [31:0] expected;
    integer    d, e;

    always @(negedge vclk) begin
        if (checking) begin
            // ---- add
            if (add_out_valid === 1'bx) n_x[0] = n_x[0] + 1;
            else if (add_out_valid) begin
                if (n_out[0] >= n_sent[0]) n_extra[0] = n_extra[0] + 1;
                else begin
                    expected = ref_add(A[n_out[0]], B[n_out[0]]);
                    if (!has_x(add_y) && !same_float(add_y, expected) && n_bad[0] < 5)
                        $display("ADD WRONG: %h + %h = %h, expected %h  [t=%0.3f ns, cycle %0d]", A[n_out[0]], B[n_out[0]], add_y, expected, $realtime, vcyc);
                    score(0, acc_cyc[n_out[0]], same_float(add_y, expected), has_x(add_y));
                end
            end
            // ---- multiply
            if (mul_out_valid === 1'bx) n_x[1] = n_x[1] + 1;
            else if (mul_out_valid) begin
                if (n_out[1] >= n_sent[1]) n_extra[1] = n_extra[1] + 1;
                else begin
                    expected = ref_mul(A[n_out[1]], B[n_out[1]]);
                    if (!has_x(mul_y) && !same_float(mul_y, expected) && n_bad[1] < 5)
                        $display("MUL WRONG: %h * %h = %h, expected %h  [t=%0.3f ns, cycle %0d]", A[n_out[1]], B[n_out[1]], mul_y, expected, $realtime, vcyc);
                    score(1, acc_cyc[n_out[1]], same_float(mul_y, expected), has_x(mul_y));
                end
            end
            // ---- shift
            if (shift_out_valid === 1'bx) n_x[2] = n_x[2] + 1;
            else if (shift_out_valid) begin
                if (n_out[2] >= n_sent[2]) n_extra[2] = n_extra[2] + 1;
                else begin
                    expected = ref_shift(A[n_out[2]], K[n_out[2]]);
                    if (!has_x(shift_y) && !same_float(shift_y, expected) && n_bad[2] < 5)
                        $display("SHIFT WRONG: %h * 2^%0d = %h, expected %h  [t=%0.3f ns, cycle %0d]", A[n_out[2]], K[n_out[2]], shift_y, expected, $realtime, vcyc);
                    score(2, acc_cyc[n_out[2]], same_float(shift_y, expected), has_x(shift_y));
                end
            end
            // ---- exp
            if (exp_out_valid === 1'bx) n_x[3] = n_x[3] + 1;
            else if (exp_out_valid) begin
                if (n_out[3] >= n_sent[3]) n_extra[3] = n_extra[3] + 1;
                else begin
                    expected = ref_exp(X[n_out[3]]);
                    d = has_x(exp_y) ? 0 : ulp_diff(exp_y, expected);
                    if (d > exp_worst_ulp) exp_worst_ulp = d;
                    if (d > EXP_ULP_LIMIT && n_bad[3] < 5)
                        $display("EXP WRONG: e^%h = %h, expected %h (%0d ulp)  [t=%0.3f ns, cycle %0d]", X[n_out[3]], exp_y, expected, d, $realtime, vcyc);
                    if (n_out[3] < N_DIR)
                        $display("  exp  e^(%g) = %h  (%g)", f2r(X[n_out[3]]), exp_y, f2r(exp_y));
                    score(3, acc_cyc[n_out[3]], d <= EXP_ULP_LIMIT, has_x(exp_y));
                end
            end
            // ---- BRAM
            if (bram_rvalid === 1'bx) n_x[4] = n_x[4] + 1;
            else if (bram_rvalid) begin
                if (n_out[4] >= n_sent[4]) n_extra[4] = n_extra[4] + 1;
                else begin
                    e = rd_entry[n_out[4]];
                    score(4, rd_cyc[n_out[4]], bram_rdata === bdata[e], has_x(bram_rdata));
                end
            end
            // ---- URAM
            if (uram_rvalid === 1'bx) n_x[5] = n_x[5] + 1;
            else if (uram_rvalid) begin
                if (n_out[5] >= n_sent[5]) n_extra[5] = n_extra[5] + 1;
                else begin
                    e = rd_entry[n_out[5]];
                    score(5, rd_cyc[n_out[5]], uram_rdata === udata[e], has_x(uram_rdata));
                end
            end
            // ---- DDR4 (fake memory)
            if (ddr_done === 1'bx) n_x[6] = n_x[6] + 1;
            else if (ddr_done) begin
                if (n_out[6] >= n_sent[6]) n_extra[6] = n_extra[6] + 1;
                else begin
                    ddr_reported = ddr_latency_cycles;
                    score(6, ddr_req_cyc[n_out[6]],
                          ddr_rdata[39:0] === ddr_req_addr[n_out[6]], has_x(ddr_rdata));
                end
            end
        end
        vcyc = vcyc + 1;                 // count cycles AFTER checking
    end

    // ------------------------------------------------------------- driver tasks
    // Call these right after @(posedge vclk).
    task send_math(input integer idx);
        begin
            add_in_valid = 1;   add_a = A[idx];   add_b = B[idx];
            mul_in_valid = 1;   mul_a = A[idx];   mul_b = B[idx];
            shift_in_valid = 1; shift_a = A[idx]; shift_k = K[idx];
            exp_in_valid = 1;   exp_a = X[idx];
            acc_cyc[idx] = vcyc;
            n_sent[0] = n_sent[0] + 1;  n_sent[1] = n_sent[1] + 1;
            n_sent[2] = n_sent[2] + 1;  n_sent[3] = n_sent[3] + 1;
        end
    endtask

    task idle_math;
        begin
            add_in_valid = 0; mul_in_valid = 0; shift_in_valid = 0; exp_in_valid = 0;
        end
    endtask

    task send_read(input integer word);  // read the same word index from BRAM and URAM
        begin
            bram_re = 1; bram_addr = baddr[word];
            uram_re = 1; uram_addr = uaddr[word];
            rd_entry[n_rd] = word;  rd_cyc[n_rd] = vcyc;  n_rd = n_rd + 1;
            n_sent[4] = n_sent[4] + 1;  n_sent[5] = n_sent[5] + 1;
        end
    endtask

    // wait until units first..last have answered everything (or time out)
    task wait_for_answers(input integer first, input integer last, input integer max_cycles);
        integer t, w, done_all;
        begin
            done_all = 0;
            for (t = 0; t < max_cycles && !done_all; t = t + 1) begin
                @(posedge vclk);
                done_all = 1;
                for (w = first; w <= last; w = w + 1)
                    if (n_out[w] < n_sent[w]) done_all = 0;
            end
        end
    endtask

    // ------------------------------------------------------------- main sequence
    real t_edge, clk_to_out;
    integer pass_all;

    initial begin
        // 1. Hold reset. Wait 300 ns first: in timing simulation the chip's
        //    global reset (GSR) holds every register for the first 100 ns.
        #300;
        repeat (5) @(posedge clk);

        // 2. Measure how long after a clk edge the outputs change.
        //    (fork/join runs both branches at once, like two threads; whichever
        //    finishes first 'disable's the other. The second one is a timeout
        //    in case heartbeat never moves, e.g. a broken netlist.)
        @(posedge clk);
        t_edge = $realtime;
        clk_to_out = -1.0;
        fork : measure
            begin @(heartbeat); clk_to_out = $realtime - t_edge; disable measure; end
            begin #(10 * CLK_NS); disable measure; end
        join
        if (clk_to_out < 0) begin
            $display("ERROR: heartbeat never changed -- the design is not running");
            print_results;
            $finish;
        end
        offset_ns  = clk_to_out + 0.1 * CLK_NS;
        while (offset_ns >= CLK_NS) offset_ns = offset_ns - CLK_NS;
        $display("clock %0.3f ns (%0.1f MHz): outputs change %0.3f ns after clk; testbench drives %0.3f ns after clk",
                 CLK_NS, 1000.0 / CLK_NS, clk_to_out, offset_ns);
        repeat (4) @(posedge vclk);

        // 3. Release reset, let it flush through, start checking.
        @(posedge vclk) rst = 0;
        repeat (40) @(posedge vclk);
        checking = 1;

        // 4. Math, isolated: one problem in flight at a time.
        for (i = 0; i < N_DIR; i = i + 1) begin
            @(posedge vclk) send_math(i);
            @(posedge vclk) idle_math;
            wait_for_answers(0, 3, 200);
        end

        // 5. Math, continuous: a new problem every cycle.
        for (i = N_DIR; i < N_TOTAL; i = i + 1)
            @(posedge vclk) send_math(i);
        @(posedge vclk) idle_math;
        wait_for_answers(0, 3, 300);

        // 6. Memories: write NM words back to back.
        for (j = 0; j < NM; j = j + 1) begin
            @(posedge vclk);
            bram_we = 1; bram_addr = baddr[j]; bram_wdata = bdata[j];
            uram_we = 1; uram_addr = uaddr[j]; uram_wdata = udata[j];
        end
        @(posedge vclk) begin bram_we = 0; uram_we = 0; end
        repeat (4) @(posedge vclk);

        //    isolated reads
        for (j = 0; j < NM; j = j + 1) begin
            @(posedge vclk) send_read(j);
            @(posedge vclk) begin bram_re = 0; uram_re = 0; end
            wait_for_answers(4, 5, 50);
        end
        //    back-to-back reads, address changing every cycle, shuffled order
        for (j = 0; j < NM; j = j + 1)
            @(posedge vclk) send_read((j * 7) % NM);
        @(posedge vclk) begin bram_re = 0; uram_re = 0; end
        wait_for_answers(4, 5, 50);

        // 7. DDR4 reads through the fake model, one at a time.
        for (j = 0; j < 3; j = j + 1) begin
            @(posedge vclk) begin
                ddr_start = 1; ddr_addr = ddr_req_addr[j];
                ddr_req_cyc[j] = vcyc;  n_sent[6] = n_sent[6] + 1;
            end
            @(posedge vclk) ddr_start = 0;
            wait_for_answers(6, 6, 500);
        end
        repeat (10) @(posedge vclk);

        // 8. Report
        print_results;
        $finish;
    end

    // Safety net: stop if something hangs
    initial begin
        #((N_RANDOM + 30000) * CLK_NS + 1000);
        $display("TIMEOUT: simulation did not finish");
        print_results;
        $finish;
    end

    task print_one(input integer unit, input [8*10-1:0] name);
        integer missing, ok;
        begin
            missing = n_sent[unit] - n_out[unit];
            ok = (n_bad[unit] == 0) && (n_x[unit] == 0) && (missing == 0) && (n_extra[unit] == 0)
                 && (lat_min[unit] == lat_max[unit]) && (n_sent[unit] > 0);
            if (!ok) pass_all = 0;
            $display("%-10s %4d cyc %8.2f ns  %6d   %6d   %5d  %3d  %5d  %5d   %0s",
                     name, lat_max[unit], lat_max[unit] * CLK_NS, n_sent[unit], n_ok[unit], n_bad[unit],
                     n_x[unit], missing, n_extra[unit], ok ? "PASS" : "FAIL");
            // machine-readable line for the sweep script
            $display("RESULT unit=%0s sent=%0d correct=%0d wrong=%0d x=%0d missing=%0d extra=%0d lat_min=%0d lat_max=%0d",
                     name, n_sent[unit], n_ok[unit], n_bad[unit], n_x[unit], missing, n_extra[unit],
                     lat_min[unit], lat_max[unit]);
        end
    endtask

    task print_results;
        begin
            pass_all = 1;
            $display("");
            $display("==================== RESULTS (clock %0.3f ns = %0.1f MHz) ====================",
                     CLK_NS, 1000.0 / CLK_NS);
            $display("unit       latency   time         sent  correct  wrong    X  missing extra  verdict");
            print_one(0, "add");
            print_one(1, "multiply");
            print_one(2, "shift");
            print_one(3, "exp");
            print_one(4, "bram_read");
            print_one(5, "uram_read");
            print_one(6, "ddr4_read");
            $display("exp worst error: %0d ulp (limit %0d)", exp_worst_ulp, EXP_ULP_LIMIT);
            $display("ddr4: unit counted %0d cycles -- FAKE model delay; real DDR4 needs the board", ddr_reported);
            $display("Latency = cycles inside the unit (the %0d boundary-register cycles are subtracted).", BOUNDARY_CYCLES);
            $display("OVERALL %0s", pass_all ? "PASS" : "FAIL");
        end
    endtask

endmodule
