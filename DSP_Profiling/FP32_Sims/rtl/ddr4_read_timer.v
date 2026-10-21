`timescale 1ns/1ps
// =============================================================================
// ddr4_read_timer.v  --  read one word from DDR4 and count how long it took
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// WHERE DDR4 IS ON THE KR260
//   The 4 GB of DDR4 is wired to the Zynq's processor side (the "PS"), not
//   to the FPGA fabric (the "PL") where our logic lives. Our logic can only
//   reach it through the PS, over a bus called AXI. So this module is an
//   "AXI master": it sends the PS a read request and waits for the data.
//   On the board, its m_axi_* pins get connected to a PS port (e.g. S_AXI_HP0)
//   in a Vivado block design.
//
// AXI READ IN 2 STEPS (a "handshake" = both sides agree in the same cycle)
//   1. Address channel: we raise ARVALID with the address in ARADDR.
//      The PS raises ARREADY when it accepts. Both high = address sent.
//   2. Data channel: we keep RREADY high. When the data comes back the PS
//      raises RVALID with the data in RDATA. RLAST = 1 marks the last word.
//
// WHAT IT MEASURES
//   latency_cycles = cycles from 'start' until the data arrives. Time in ns
//   = latency_cycles * clock period. Real DDR4 timing can only be measured
//   on the board; in simulation (sim/axi_mem_model.v) the delay is made up.
//
// STATE MACHINE (like a C switch inside a while loop, one step per cycle)
//   IDLE -> (start) -> SEND_ADDR -> (ARREADY) -> WAIT_DATA -> (RVALID & RLAST) -> IDLE
// =============================================================================
module ddr4_read_timer (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,                // pulse for 1 cycle to begin a read
    input  wire [39:0]  addr,                 // byte address (PS address map)
    output reg          done,                 // 1 for one cycle when data is back
    output reg  [127:0] rdata,                // the 16 bytes that were read
    output reg  [15:0]  latency_cycles,       // how long the read took

    // ---- AXI4 read address channel (we -> PS)
    output reg  [39:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,          // beats in the burst minus 1 (0 = one beat)
    output wire [2:0]   m_axi_arsize,         // bytes per beat as a power of 2
    output wire [1:0]   m_axi_arburst,        // burst type
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    // ---- AXI4 read data channel (PS -> us)
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,          // 0 = OK (not checked here)
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready
);
    // Fixed settings: a single beat of 16 bytes (128 bits)
    assign m_axi_arlen   = 8'd0;              // 1 beat
    assign m_axi_arsize  = 3'd4;              // 2^4 = 16 bytes per beat
    assign m_axi_arburst = 2'b01;             // INCR (normal incrementing burst)

    // State names (like a C enum)
    localparam IDLE      = 2'd0;
    localparam SEND_ADDR = 2'd1;
    localparam WAIT_DATA = 2'd2;

    reg [1:0]  state;
    reg [15:0] counter;                       // counts cycles while a read is in flight

    always @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
            done           <= 1'b0;
            counter        <= 16'd0;
            latency_cycles <= 16'd0;
        end else begin
            done <= 1'b0;                     // default: done is a 1-cycle pulse

            case (state)
                IDLE: begin
                    if (start) begin
                        m_axi_araddr  <= addr;
                        m_axi_arvalid <= 1'b1;    // offer the address
                        counter       <= 16'd1;   // this cycle counts as cycle 1
                        state         <= SEND_ADDR;
                    end
                end

                SEND_ADDR: begin
                    counter <= counter + 16'd1;
                    if (m_axi_arready) begin      // PS accepted the address
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;    // ready to receive data
                        state         <= WAIT_DATA;
                    end
                end

                WAIT_DATA: begin
                    counter <= counter + 16'd1;
                    if (m_axi_rvalid && m_axi_rlast) begin   // data is here
                        rdata          <= m_axi_rdata;
                        latency_cycles <= counter;
                        m_axi_rready   <= 1'b0;
                        done           <= 1'b1;
                        state          <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
