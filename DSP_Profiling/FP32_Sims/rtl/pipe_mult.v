`timescale 1ns/1ps
// =============================================================================
// pipe_mult.v  --  pipelined unsigned multiplier:  p = a * b, STAGES cycles later
// =============================================================================
// *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
// WHY THIS MODULE EXISTS (from the 10/21 timing report)
//   In version 1 the multiplies had only one register after them. A wide
//   multiply is built from several DSP48E2 slices chained together (each
//   slice is 27 x 18 bits), and without enough registers the signal has to
//   ripple through the whole chain in one clock cycle. The report's worst
//   path at 300 MHz was exactly that: one DSP multiply feeding the next
//   in fp_exp (3.4 ns of delay in a 3.3 ns clock).
//
// HOW THE STAGES ARE USED
//   cycle 1        : register a and b          (DSP's built-in A/B registers)
//   cycle 2        : multiply                  (DSP's built-in M register)
//   cycles 3..S    : extra registers           (DSP's P register + registers
//                                               between chained DSP slices)
//   Vivado moves these registers INTO the DSP slices. More DSP slices in the
//   chain -> use more stages. Rule of thumb used here:
//       up to 2 DSP slices: STAGES = 4,   up to 4 DSP slices: STAGES = 5
//
// Latency = STAGES cycles. A new (a, b) can go in every cycle.
// =============================================================================
module pipe_mult #(
    parameter WA     = 24,   // bits in a
    parameter WB     = 24,   // bits in b
    parameter STAGES = 4     // total cycles of latency (must be >= 3)
) (
    input  wire               clk,
    input  wire [WA-1:0]      a,
    input  wire [WB-1:0]      b,
    output wire [WA+WB-1:0]   p
);
    reg [WA-1:0] a_reg;
    reg [WB-1:0] b_reg;

    // Product registers: prod[0] holds the fresh product, prod[1], prod[2]...
    // are extra pipeline registers. srl_style = "register" stops Vivado from
    // turning them into shift-register LUTs, which could not go inside a DSP.
    (* srl_style = "register" *) reg [WA+WB-1:0] prod [0:STAGES-2];
    integer k;

    always @(posedge clk) begin
        a_reg   <= a;                         // stage 1: input registers
        b_reg   <= b;
        prod[0] <= a_reg * b_reg;             // stage 2: multiply
        for (k = 1; k < STAGES - 1; k = k + 1)
            prod[k] <= prod[k-1];             // stages 3..STAGES: extra registers
    end

    assign p = prod[STAGES-2];
endmodule
