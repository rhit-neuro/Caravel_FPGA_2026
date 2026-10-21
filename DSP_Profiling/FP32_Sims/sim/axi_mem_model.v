`timescale 1ns/1ps
// =============================================================================
// axi_mem_model.v  --  SIMULATION ONLY stand-in for the PS + DDR4
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// This is NOT real DDR4 timing. It only lets us check that ddr4_read_timer
// does the AXI handshake correctly and counts cycles correctly. It answers
// every read after a made-up delay of LATENCY cycles, and the data it
// returns is just the address, so the testbench can check it.
// Real DDR4 latency has to be measured on the KR260 board.
// =============================================================================
module axi_mem_model #(
    parameter LATENCY = 40               // made-up cycles from address to data
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [39:0]  araddr,
    input  wire         arvalid,
    output reg          arready,
    output reg  [127:0] rdata,
    output wire [1:0]   rresp,
    output reg          rlast,
    output reg          rvalid,
    input  wire         rready
);
    assign rresp = 2'b00;                // always "OK"

    reg [39:0] saved_addr;               // address of the read in progress
    integer    wait_count;               // -1 = no read in progress

    // -------------------------------------------------------------------------
    // One read at a time, as a small state machine driven by wait_count:
    //   wait_count == -1 : idle. When arvalid comes in, accept the address
    //                      (arready = 1 for one cycle) and load LATENCY.
    //   wait_count  >  0 : count down one per cycle (the made-up DDR delay).
    //   wait_count == 0  : raise rvalid/rlast with the data and hold them
    //                      until the reader takes it (rvalid && rready).
    // In C terms:  if (idle && req) n = LATENCY; else if (n > 0) n--;
    //              else if (n == 0) data_ready = 1;
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            arready <= 1'b0; rvalid <= 1'b0; rlast <= 1'b0; wait_count <= -1;
        end else begin
            arready <= 1'b0;
            if (arvalid && !arready && wait_count < 0) begin
                arready    <= 1'b1;      // accept the address
                saved_addr <= araddr;
                wait_count <= LATENCY;
            end else if (wait_count > 0) begin
                wait_count <= wait_count - 1;
            end else if (wait_count == 0 && !rvalid) begin
                rvalid <= 1'b1;          // data ready
                rlast  <= 1'b1;
                rdata  <= {88'd0, saved_addr};   // fake data = the address itself
            end
            if (rvalid && rready) begin  // data taken -> finished
                rvalid <= 1'b0; rlast <= 1'b0; wait_count <= -1;
            end
        end
    end
endmodule
