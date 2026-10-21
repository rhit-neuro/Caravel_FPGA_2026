`timescale 1ns/1ps
// =============================================================================
// bram_test.v  --  a 1024 x 32-bit memory built from Block RAM (BRAM)
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// BRAM = small, fast memory blocks spread across the FPGA (36 Kbit each;
// the KR260's chip has 144 of them). In C terms this module is:
//
//     uint32_t mem[1024];
//     if (we) mem[addr] = wdata;
//     rdata = mem[addr];          // ...but the answer arrives 2 cycles later
//
// READ LATENCY = 2 cycles:
//   cycle 1: the BRAM itself reads the address (BRAMs are always clocked)
//   cycle 2: an output register inside the BRAM, which lets it run faster
// 'rvalid' follows the same 2-cycle path so you can see when data is ready.
// =============================================================================
module bram_test (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,        // write enable
    input  wire        re,        // read enable (only used to drive rvalid)
    input  wire [9:0]  addr,      // 2^10 = 1024 locations
    input  wire [31:0] wdata,
    output reg         rvalid,    // 1 = rdata is the data you asked for 2 cycles ago
    output reg  [31:0] rdata
);
    // The memory array. The ram_style hint tells Vivado: use Block RAM.
    // Syntax: reg [width] name [depth]  ==  uint32_t mem[1024]
    (* ram_style = "block" *) reg [31:0] mem [0:1023];

    reg [31:0] read_reg;   // cycle-1 read result
    reg        re_d1;      // re delayed 1 cycle

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;        // write
        read_reg <= mem[addr];         // cycle 1: read
        rdata    <= read_reg;          // cycle 2: output register

        re_d1  <= rst ? 1'b0 : re;     // delay the read request to match
        rvalid <= rst ? 1'b0 : re_d1;
    end
endmodule
