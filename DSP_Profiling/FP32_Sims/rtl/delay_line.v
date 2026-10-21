`timescale 1ns/1ps
// =============================================================================
// delay_line.v  --  delay a signal by DEPTH clock cycles
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// In a pipeline, some signals just "ride along" without being changed (for
// example the valid flag, or a sign bit that is only needed at the end).
// They still have to arrive at the end at the same time as the data they
// belong to, so we push them through a chain of DEPTH registers:
//
//     d --> [reg] --> [reg] --> ... --> [reg] --> q      (DEPTH registers)
//
// In C terms: a FIFO of fixed length DEPTH that shifts by one every cycle.
// If rst = 1 the whole chain is cleared to 0 (used for 'valid' flags).
// Tie rst to 1'b0 for data signals; Vivado can then pack the chain into
// cheap shift-register LUTs (SRLs) instead of many flip-flops.
// =============================================================================
module delay_line #(
    parameter WIDTH = 1,     // bits per signal
    parameter DEPTH = 1      // cycles of delay (must be >= 1)
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    reg [WIDTH-1:0] stage [0:DEPTH-1];   // DEPTH registers, each WIDTH bits
    integer k;

    always @(posedge clk) begin
        stage[0] <= rst ? {WIDTH{1'b0}} : d;              // first register takes the input
        for (k = 1; k < DEPTH; k = k + 1)                 // every other register takes
            stage[k] <= rst ? {WIDTH{1'b0}} : stage[k-1]; // the one before it
    end

    assign q = stage[DEPTH-1];                            // output = last register
endmodule
