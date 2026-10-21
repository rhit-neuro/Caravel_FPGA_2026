`timescale 1ns/1ps
// =============================================================================
// fp_timing_top.v  --  PARENT MODULE for the KR260 operation-timing study (v2)
// =============================================================================
// This file does no math itself. It is like main() in C: it creates one copy
// ("instance") of each unit we want to time and wires them to the top-level
// pins. Vivado then times every unit in one build.
//
//   fp_timing_top
//    |-- u_add   : fp_add          float a + b                 (9 cycles)
//    |-- u_mul   : fp_mul          float a * b                 (8 cycles)
//    |              '-- mant_mult : pipe_mult (2 DSP slices)
//    |-- u_shift : fp_shift        float a * 2^k ("shift")     (1 cycle)
//    |-- u_exp   : fp_exp          float e^a                   (24 cycles)
//    |              |-- rom       : fp_exp2_rom (lookup table)
//    |              '-- 4 x pipe_mult
//    |-- u_bram  : bram_test       Block RAM read/write        (2-cycle read)
//    |-- u_uram  : uram_test       UltraRAM read/write         (3-cycle read)
//    '-- u_ddr4  : ddr4_read_timer reads DDR4 over AXI and counts the cycles
//   (delay_line.v and pipe_mult.v are small helpers used inside the units)
//
// "Latency" = how many clock cycles from input to answer.
// "Fmax"    = the fastest clock the circuit can run at. Only Vivado can tell
//             us this (scripts/run_timing_sweep.tcl), because it depends on
//             real wire and gate delays on the chip. Time per operation in
//             nanoseconds = latency cycles * clock period.
//
// BOUNDARY REGISTERS (new in v2)
//   Every top-level input goes through one register before reaching a unit,
//   and every unit output goes through one register before reaching a pin:
//
//      pin --> [reg] --> unit --> [reg] --> pin
//
//   Why: in the 10/21 report, the paths from the pins into the units were
//   timed with made-up pin locations (Vivado warning Route 35-198), and they
//   caused all the hold failures (e.g. pin uram_addr straight into the URAM).
//   In the real design these units will be fed by other registers on the
//   chip, so registers here are the realistic setup. The sweep script then
//   ignores the pin-to-register paths (false paths) and times what matters:
//   register -> unit -> register.
//   Cost: the testbench sees 2 extra cycles of latency (BOUNDARY_CYCLES),
//   which it subtracts to report each unit's own latency.
//
// HEARTBEAT (new in v2)
//   'heartbeat' flips every clock cycle. The testbench uses it to measure
//   how long after a clock edge the chip's outputs change (in the timing
//   simulation with real delays), so it can drive and read pins at safe times.
//
// -----------------------------------------------------------------------------
// VERILOG CHEAT SHEET FOR C PROGRAMMERS
// -----------------------------------------------------------------------------
//  Verilog describes hardware, not steps. Every line exists at the same time.
//
//  module foo(...); ... endmodule   A hardware block -- like a C function
//                                   that always runs, forever, in parallel.
//  input / output                   The block's pins (its arguments/results).
//  wire  [31:0] x;                  A 32-bit signal. It is just a wire: it
//                                   always equals whatever drives it.
//  reg   [31:0] r;                  A signal that can hold a value. When set
//                                   inside always @(posedge clk) it becomes a
//                                   flip-flop register (memory for 1 cycle).
//  assign x = a + b;                x is permanently connected to a+b.
//  always @(posedge clk) begin      Runs once on every rising clock edge.
//      r <= x;                      '<=' : all registers update together at
//  end                              the edge (no "earlier line wins" order).
//  always @(*) begin ... end        Combinational logic (no clock, no memory).
//
//  32'd5   = 32-bit decimal 5      8'hff = 8-bit hex ff      1'b1 = 1 bit "1"
//  x[31]   = bit 31 of x           x[30:23] = bits 30 down to 23 (8 bits)
//  {a, b}  = glue bits together:   {4'b1010, 4'b0011} = 8'b10100011
//  {3{1'b1}} = repeat: 3'b111      c ? a : b  = same as C
//  |x  = OR of all bits of x (1 if any bit is 1)     ~x = flip every bit
//  >>> = arithmetic shift (keeps the sign, like >> on a signed int in C)
//  signed  : treat the bits as a two's-complement signed number
//
//  foo u_name (.port(signal), ...); creates an instance of module foo,
//  connecting foo's 'port' to our 'signal' -- like calling foo(signal).
//  foo #(.N(4)) u_name (...);  also sets foo's parameter N to 4 (like a
//  compile-time constant / template argument).
//
//  (* use_dsp = "yes" *), (* ram_style = "block" *)  are hints to Vivado
//  telling it which kind of chip resource to build that line with.
// =============================================================================
module fp_timing_top (
    input  wire         clk,          // one clock drives every unit
    input  wire         rst,          // reset: clears the "valid" flags
    output reg          heartbeat,    // flips every cycle (for the testbench)

    // ---------------- adder: add_y = add_a + add_b
    input  wire         add_in_valid, // 1 = add_a/add_b hold a new problem this cycle
    input  wire [31:0]  add_a,
    input  wire [31:0]  add_b,
    output reg          add_out_valid,// 1 = add_y holds an answer this cycle
    output reg  [31:0]  add_y,

    // ---------------- multiplier: mul_y = mul_a * mul_b
    input  wire         mul_in_valid,
    input  wire [31:0]  mul_a,
    input  wire [31:0]  mul_b,
    output reg          mul_out_valid,
    output reg  [31:0]  mul_y,

    // ---------------- shift: shift_y = shift_a * 2^shift_k
    input  wire         shift_in_valid,
    input  wire [31:0]  shift_a,
    input  wire signed [8:0] shift_k, // -256..255
    output reg          shift_out_valid,
    output reg  [31:0]  shift_y,

    // ---------------- exponential: exp_y = e^exp_a
    input  wire         exp_in_valid,
    input  wire [31:0]  exp_a,
    output reg          exp_out_valid,
    output reg  [31:0]  exp_y,

    // ---------------- Block RAM: 1024 words x 32 bits
    input  wire         bram_we,      // 1 = write bram_wdata to bram_addr
    input  wire         bram_re,      // 1 = read bram_addr
    input  wire [9:0]   bram_addr,
    input  wire [31:0]  bram_wdata,
    output reg          bram_rvalid,  // 1 = bram_rdata holds read data
    output reg  [31:0]  bram_rdata,

    // ---------------- UltraRAM: 4096 words x 32 bits
    input  wire         uram_we,
    input  wire         uram_re,
    input  wire [11:0]  uram_addr,
    input  wire [31:0]  uram_wdata,
    output reg          uram_rvalid,
    output reg  [31:0]  uram_rdata,

    // ---------------- DDR4 read timer
    input  wire         ddr_start,    // pulse 1 for one cycle to start a read
    input  wire [39:0]  ddr_addr,     // byte address in DDR4
    output reg          ddr_done,     // 1 for one cycle when the data is back
    output reg  [127:0] ddr_rdata,
    output reg  [15:0]  ddr_latency_cycles, // how many cycles the read took
    // AXI4 read port -> on the board this connects to the Zynq PS
    // (the DDR4 on the KR260 is wired to the PS side, not to our logic).
    // NOTE: these also pass through boundary registers here, which is fine
    // for timing the unit but adds cycles; on the board, connect u_ddr4's
    // m_axi_* pins straight to the PS instead.
    output reg  [39:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,
    output reg  [2:0]   m_axi_arsize,
    output reg  [1:0]   m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready
);

    // =========================================================================
    // INPUT BOUNDARY REGISTERS: pin -> register (names end in _q)
    // =========================================================================
    reg         rst_q;
    reg         add_in_valid_q, mul_in_valid_q, shift_in_valid_q, exp_in_valid_q;
    reg  [31:0] add_a_q, add_b_q, mul_a_q, mul_b_q, shift_a_q, exp_a_q;
    reg  signed [8:0] shift_k_q;
    reg         bram_we_q, bram_re_q, uram_we_q, uram_re_q;
    reg  [9:0]  bram_addr_q;
    reg  [11:0] uram_addr_q;
    reg  [31:0] bram_wdata_q, uram_wdata_q;
    reg         ddr_start_q;
    reg  [39:0] ddr_addr_q;
    reg         m_axi_arready_q, m_axi_rlast_q, m_axi_rvalid_q;
    reg  [127:0] m_axi_rdata_q;
    reg  [1:0]  m_axi_rresp_q;

    always @(posedge clk) begin
        rst_q            <= rst;
        add_in_valid_q   <= add_in_valid;    add_a_q   <= add_a;    add_b_q <= add_b;
        mul_in_valid_q   <= mul_in_valid;    mul_a_q   <= mul_a;    mul_b_q <= mul_b;
        shift_in_valid_q <= shift_in_valid;  shift_a_q <= shift_a;  shift_k_q <= shift_k;
        exp_in_valid_q   <= exp_in_valid;    exp_a_q   <= exp_a;
        bram_we_q <= bram_we;  bram_re_q <= bram_re;  bram_addr_q <= bram_addr;  bram_wdata_q <= bram_wdata;
        uram_we_q <= uram_we;  uram_re_q <= uram_re;  uram_addr_q <= uram_addr;  uram_wdata_q <= uram_wdata;
        ddr_start_q      <= ddr_start;       ddr_addr_q <= ddr_addr;
        m_axi_arready_q  <= m_axi_arready;   m_axi_rdata_q <= m_axi_rdata;
        m_axi_rresp_q    <= m_axi_rresp;     m_axi_rlast_q <= m_axi_rlast;
        m_axi_rvalid_q   <= m_axi_rvalid;
    end

    // heartbeat: starts at 0 (the "= 1'b0" is the power-up value) and flips every cycle
    initial heartbeat = 1'b0;
    always @(posedge clk) heartbeat <= ~heartbeat;

    // =========================================================================
    // UNITS. Read ".x(y)" as "connect the submodule's pin x to our signal y".
    // Unit outputs are wires named *_u; they get registered below.
    // =========================================================================
    wire         add_out_valid_u, mul_out_valid_u, shift_out_valid_u, exp_out_valid_u;
    wire [31:0]  add_y_u, mul_y_u, shift_y_u, exp_y_u;
    wire         bram_rvalid_u, uram_rvalid_u;
    wire [31:0]  bram_rdata_u, uram_rdata_u;
    wire         ddr_done_u;
    wire [127:0] ddr_rdata_u;
    wire [15:0]  ddr_latency_cycles_u;
    wire [39:0]  araddr_u;
    wire [7:0]   arlen_u;
    wire [2:0]   arsize_u;
    wire [1:0]   arburst_u;
    wire         arvalid_u, rready_u;

    fp_add u_add (
        .clk(clk), .rst(rst_q),
        .in_valid(add_in_valid_q), .a(add_a_q), .b(add_b_q),
        .out_valid(add_out_valid_u), .y(add_y_u)
    );

    fp_mul u_mul (
        .clk(clk), .rst(rst_q),
        .in_valid(mul_in_valid_q), .a(mul_a_q), .b(mul_b_q),
        .out_valid(mul_out_valid_u), .y(mul_y_u)
    );

    fp_shift u_shift (
        .clk(clk), .rst(rst_q),
        .in_valid(shift_in_valid_q), .a(shift_a_q), .k(shift_k_q),
        .out_valid(shift_out_valid_u), .y(shift_y_u)
    );

    fp_exp u_exp (
        .clk(clk), .rst(rst_q),
        .in_valid(exp_in_valid_q), .a(exp_a_q),
        .out_valid(exp_out_valid_u), .y(exp_y_u)
    );

    bram_test u_bram (
        .clk(clk), .rst(rst_q),
        .we(bram_we_q), .re(bram_re_q), .addr(bram_addr_q), .wdata(bram_wdata_q),
        .rvalid(bram_rvalid_u), .rdata(bram_rdata_u)
    );

    uram_test u_uram (
        .clk(clk), .rst(rst_q),
        .we(uram_we_q), .re(uram_re_q), .addr(uram_addr_q), .wdata(uram_wdata_q),
        .rvalid(uram_rvalid_u), .rdata(uram_rdata_u)
    );

    ddr4_read_timer u_ddr4 (
        .clk(clk), .rst(rst_q),
        .start(ddr_start_q), .addr(ddr_addr_q),
        .done(ddr_done_u), .rdata(ddr_rdata_u), .latency_cycles(ddr_latency_cycles_u),
        .m_axi_araddr(araddr_u), .m_axi_arlen(arlen_u),
        .m_axi_arsize(arsize_u), .m_axi_arburst(arburst_u),
        .m_axi_arvalid(arvalid_u), .m_axi_arready(m_axi_arready_q),
        .m_axi_rdata(m_axi_rdata_q), .m_axi_rresp(m_axi_rresp_q),
        .m_axi_rlast(m_axi_rlast_q), .m_axi_rvalid(m_axi_rvalid_q),
        .m_axi_rready(rready_u)
    );

    // =========================================================================
    // OUTPUT BOUNDARY REGISTERS: unit -> register -> pin
    // =========================================================================
    always @(posedge clk) begin
        add_out_valid   <= add_out_valid_u;    add_y   <= add_y_u;
        mul_out_valid   <= mul_out_valid_u;    mul_y   <= mul_y_u;
        shift_out_valid <= shift_out_valid_u;  shift_y <= shift_y_u;
        exp_out_valid   <= exp_out_valid_u;    exp_y   <= exp_y_u;
        bram_rvalid     <= bram_rvalid_u;      bram_rdata <= bram_rdata_u;
        uram_rvalid     <= uram_rvalid_u;      uram_rdata <= uram_rdata_u;
        ddr_done        <= ddr_done_u;         ddr_rdata  <= ddr_rdata_u;
        ddr_latency_cycles <= ddr_latency_cycles_u;
        m_axi_araddr  <= araddr_u;   m_axi_arlen  <= arlen_u;  m_axi_arsize <= arsize_u;
        m_axi_arburst <= arburst_u;  m_axi_arvalid <= arvalid_u;  m_axi_rready <= rready_u;
    end

endmodule
