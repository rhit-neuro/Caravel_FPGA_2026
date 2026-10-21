`timescale 1ns/1ps
// =============================================================================
// uram_test.v  --  a 4096 x 32-bit memory built from UltraRAM (URAM)
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// URAM = bigger memory blocks than BRAM (288 Kbit each, 8x a BRAM; the
// KR260's chip has 64 of them). Good for storing lots of neuron state.
// Same idea as bram_test.v:
//
//     uint32_t mem[4096];
//     if (we) mem[addr] = wdata;
//     rdata = mem[addr];          // ...answer arrives 3 cycles later
//
// READ LATENCY = 3 cycles. URAM is slower inside than BRAM, so it needs one
// more pipeline register to reach a high clock speed:
//   cycle 1: the URAM reads the address
//   cycle 2: pipeline register 1
//   cycle 3: pipeline register 2
// Vivado pulls these registers into the URAM block itself.
// =============================================================================
module uram_test (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire        re,
    input  wire [11:0] addr,      // 2^12 = 4096 locations
    input  wire [31:0] wdata,
    output reg         rvalid,
    output reg  [31:0] rdata
);
    // The ram_style hint tells Vivado: use UltraRAM.
    (* ram_style = "ultra" *) reg [31:0] mem [0:4095];

    reg [31:0] read_reg, pipe_reg;
    reg        re_d1, re_d2;

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;        // write
        read_reg <= mem[addr];         // cycle 1: read
        pipe_reg <= read_reg;          // cycle 2
        rdata    <= pipe_reg;          // cycle 3

        re_d1  <= rst ? 1'b0 : re;     // delay the read request 3 cycles to match
        re_d2  <= rst ? 1'b0 : re_d1;
        rvalid <= rst ? 1'b0 : re_d2;
    end
endmodule
