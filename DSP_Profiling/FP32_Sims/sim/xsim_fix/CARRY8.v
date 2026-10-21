// =============================================================================
// CARRY8.v  --  copy of AMD's CARRY8 simulation model (Vivado 2023.2,
//               data/verilog/src/unisims/CARRY8.v) with ONE change, used ONLY
//               for the post-route timing simulations in run_timing_sweep.tcl
// =============================================================================
// WHAT CARRY8 IS
//   The chip's built-in 8-bit carry chain (the fast "ripple carry" next to the
//   LUTs). Synthesis uses it for every adder/comparator. Bit by bit:
//       O[k]  = S[k] ^ carry_in[k]                (sum bit)
//       CO[k] = S[k] ? carry_in[k] : DI[k]         (carry out)
//       carry_in[0] = CI, carry_in[k] = CO[k-1]
//   Like a C loop:  c = CI; for (k=0;k<8;k++){ O[k]=S[k]^c; c = S[k]?c:DI[k]; CO[k]=c; }
//
// WHY THIS COPY EXISTS (found 2026-10-21)
//   AMD's model feeds the carry back by reading its OWN output port CO
//   ("CO_fb = {CO[6:4], CI_TOP_in, CO[2:0], CI_in}"). In a timing simulation
//   that output port carries the SDF path delays, and Vivado 2023.2's xsim
//   then let a stale sum land AFTER the correct one: in the 12 MHz slow-corner
//   run, adder cell u_add/s5_sum_reg[27]_i_1 had stable inputs for 80 ns, its
//   own internal signals said O = 1001, but its O pin stayed at 0111.
//   A real carry chain cannot do that, so the adder "failed" in simulation only.
//   (Static timing had 80 ns of slack on that path; the same netlist with
//   zero delays got every answer right.)
//
// THE ONE CHANGE
//   The carry is computed on internal wires (carry_in / carry_out below)
//   instead of being read back from the CO output pin, and each output bit
//   gets its own assign. The logic function, the ports, and the specify block
//   (the list of pin-to-pin delays the SDF file fills in) are copied unchanged,
//   so every SDF delay still applies exactly as before.
// =============================================================================

`timescale 1 ps / 1 ps

`celldefine

module CARRY8 #(
  parameter LOC = "UNPLACED",
  parameter CARRY_TYPE = "SINGLE_CY8"
)(
  output [7:0] CO,
  output [7:0] O,

  input CI,
  input CI_TOP,
  input [7:0] DI,
  input [7:0] S
);

  // unconnected (z) inputs read as 0, same as AMD's model
  wire       CI_in     = (CI !== 1'bz) && CI;
  wire       CI_TOP_in = (CI_TOP !== 1'bz) && CI_TOP;
  wire [7:0] DI_in, S_in;
  genvar k;
  generate
    for (k = 0; k < 8; k = k + 1) begin : g_in
      assign DI_in[k] = (DI[k] !== 1'bz) && DI[k];
      assign S_in[k]  = (S[k]  !== 1'bz) && S[k];
    end
  endgenerate

  // carry chain on internal wires (never reads the CO output pin back)
  //   SINGLE_CY8: one 8-bit chain, bit 4 continues from bit 3
  //   DUAL_CY4  : two 4-bit chains, bit 4 starts from CI_TOP
  wire [7:0] carry_in, carry_out;
  assign carry_in[0] = CI_in;
  generate
    for (k = 1; k < 8; k = k + 1) begin : g_cin
      if (k == 4)
        assign carry_in[k] = (CARRY_TYPE == "DUAL_CY4") ? CI_TOP_in : carry_out[3];
      else
        assign carry_in[k] = carry_out[k-1];
    end
    for (k = 0; k < 8; k = k + 1) begin : g_out
      assign carry_out[k] = S_in[k] ? carry_in[k] : DI_in[k];
      assign O[k]  = S_in[k] ^ carry_in[k];   // one assign per output bit
      assign CO[k] = carry_out[k];
    end
  endgenerate

  // ---- pin-to-pin delays: copied unchanged from AMD's model (SDF fills these in)
  specify
    (CI => CO[0]) = (0:0:0, 0:0:0);
    (CI => CO[1]) = (0:0:0, 0:0:0);
    (CI => CO[2]) = (0:0:0, 0:0:0);
    (CI => CO[3]) = (0:0:0, 0:0:0);
    (CI => CO[4]) = (0:0:0, 0:0:0);
    (CI => CO[5]) = (0:0:0, 0:0:0);
    (CI => CO[6]) = (0:0:0, 0:0:0);
    (CI => CO[7]) = (0:0:0, 0:0:0);
    (CI => O[0]) = (0:0:0, 0:0:0);
    (CI => O[1]) = (0:0:0, 0:0:0);
    (CI => O[2]) = (0:0:0, 0:0:0);
    (CI => O[3]) = (0:0:0, 0:0:0);
    (CI => O[4]) = (0:0:0, 0:0:0);
    (CI => O[5]) = (0:0:0, 0:0:0);
    (CI => O[6]) = (0:0:0, 0:0:0);
    (CI => O[7]) = (0:0:0, 0:0:0);
    (CI_TOP => CO[4]) = (0:0:0, 0:0:0);
    (CI_TOP => CO[5]) = (0:0:0, 0:0:0);
    (CI_TOP => CO[6]) = (0:0:0, 0:0:0);
    (CI_TOP => CO[7]) = (0:0:0, 0:0:0);
    (CI_TOP => O[4]) = (0:0:0, 0:0:0);
    (CI_TOP => O[5]) = (0:0:0, 0:0:0);
    (CI_TOP => O[6]) = (0:0:0, 0:0:0);
    (CI_TOP => O[7]) = (0:0:0, 0:0:0);
    (DI[0] => CO[0]) = (0:0:0, 0:0:0);
    (DI[0] => CO[1]) = (0:0:0, 0:0:0);
    (DI[0] => CO[2]) = (0:0:0, 0:0:0);
    (DI[0] => CO[3]) = (0:0:0, 0:0:0);
    (DI[0] => CO[4]) = (0:0:0, 0:0:0);
    (DI[0] => CO[5]) = (0:0:0, 0:0:0);
    (DI[0] => CO[6]) = (0:0:0, 0:0:0);
    (DI[0] => CO[7]) = (0:0:0, 0:0:0);
    (DI[0] => O[0]) = (0:0:0, 0:0:0);
    (DI[0] => O[1]) = (0:0:0, 0:0:0);
    (DI[0] => O[2]) = (0:0:0, 0:0:0);
    (DI[0] => O[3]) = (0:0:0, 0:0:0);
    (DI[0] => O[4]) = (0:0:0, 0:0:0);
    (DI[0] => O[5]) = (0:0:0, 0:0:0);
    (DI[0] => O[6]) = (0:0:0, 0:0:0);
    (DI[0] => O[7]) = (0:0:0, 0:0:0);
    (DI[1] => CO[1]) = (0:0:0, 0:0:0);
    (DI[1] => CO[2]) = (0:0:0, 0:0:0);
    (DI[1] => CO[3]) = (0:0:0, 0:0:0);
    (DI[1] => CO[4]) = (0:0:0, 0:0:0);
    (DI[1] => CO[5]) = (0:0:0, 0:0:0);
    (DI[1] => CO[6]) = (0:0:0, 0:0:0);
    (DI[1] => CO[7]) = (0:0:0, 0:0:0);
    (DI[1] => O[2]) = (0:0:0, 0:0:0);
    (DI[1] => O[3]) = (0:0:0, 0:0:0);
    (DI[1] => O[4]) = (0:0:0, 0:0:0);
    (DI[1] => O[5]) = (0:0:0, 0:0:0);
    (DI[1] => O[6]) = (0:0:0, 0:0:0);
    (DI[1] => O[7]) = (0:0:0, 0:0:0);
    (DI[2] => CO[2]) = (0:0:0, 0:0:0);
    (DI[2] => CO[3]) = (0:0:0, 0:0:0);
    (DI[2] => CO[4]) = (0:0:0, 0:0:0);
    (DI[2] => CO[5]) = (0:0:0, 0:0:0);
    (DI[2] => CO[6]) = (0:0:0, 0:0:0);
    (DI[2] => CO[7]) = (0:0:0, 0:0:0);
    (DI[2] => O[3]) = (0:0:0, 0:0:0);
    (DI[2] => O[4]) = (0:0:0, 0:0:0);
    (DI[2] => O[5]) = (0:0:0, 0:0:0);
    (DI[2] => O[6]) = (0:0:0, 0:0:0);
    (DI[2] => O[7]) = (0:0:0, 0:0:0);
    (DI[3] => CO[3]) = (0:0:0, 0:0:0);
    (DI[3] => CO[4]) = (0:0:0, 0:0:0);
    (DI[3] => CO[5]) = (0:0:0, 0:0:0);
    (DI[3] => CO[6]) = (0:0:0, 0:0:0);
    (DI[3] => CO[7]) = (0:0:0, 0:0:0);
    (DI[3] => O[4]) = (0:0:0, 0:0:0);
    (DI[3] => O[5]) = (0:0:0, 0:0:0);
    (DI[3] => O[6]) = (0:0:0, 0:0:0);
    (DI[3] => O[7]) = (0:0:0, 0:0:0);
    (DI[4] => CO[4]) = (0:0:0, 0:0:0);
    (DI[4] => CO[5]) = (0:0:0, 0:0:0);
    (DI[4] => CO[6]) = (0:0:0, 0:0:0);
    (DI[4] => CO[7]) = (0:0:0, 0:0:0);
    (DI[4] => O[5]) = (0:0:0, 0:0:0);
    (DI[4] => O[6]) = (0:0:0, 0:0:0);
    (DI[4] => O[7]) = (0:0:0, 0:0:0);
    (DI[5] => CO[5]) = (0:0:0, 0:0:0);
    (DI[5] => CO[6]) = (0:0:0, 0:0:0);
    (DI[5] => CO[7]) = (0:0:0, 0:0:0);
    (DI[5] => O[6]) = (0:0:0, 0:0:0);
    (DI[5] => O[7]) = (0:0:0, 0:0:0);
    (DI[6] => CO[6]) = (0:0:0, 0:0:0);
    (DI[6] => CO[7]) = (0:0:0, 0:0:0);
    (DI[6] => O[7]) = (0:0:0, 0:0:0);
    (DI[7] => CO[7]) = (0:0:0, 0:0:0);
    (S[0] => CO[0]) = (0:0:0, 0:0:0);
    (S[0] => CO[1]) = (0:0:0, 0:0:0);
    (S[0] => CO[2]) = (0:0:0, 0:0:0);
    (S[0] => CO[3]) = (0:0:0, 0:0:0);
    (S[0] => CO[4]) = (0:0:0, 0:0:0);
    (S[0] => CO[5]) = (0:0:0, 0:0:0);
    (S[0] => CO[6]) = (0:0:0, 0:0:0);
    (S[0] => CO[7]) = (0:0:0, 0:0:0);
    (S[0] => O[0]) = (0:0:0, 0:0:0);
    (S[0] => O[1]) = (0:0:0, 0:0:0);
    (S[0] => O[2]) = (0:0:0, 0:0:0);
    (S[0] => O[3]) = (0:0:0, 0:0:0);
    (S[0] => O[4]) = (0:0:0, 0:0:0);
    (S[0] => O[5]) = (0:0:0, 0:0:0);
    (S[0] => O[6]) = (0:0:0, 0:0:0);
    (S[0] => O[7]) = (0:0:0, 0:0:0);
    (S[1] => CO[1]) = (0:0:0, 0:0:0);
    (S[1] => CO[2]) = (0:0:0, 0:0:0);
    (S[1] => CO[3]) = (0:0:0, 0:0:0);
    (S[1] => CO[4]) = (0:0:0, 0:0:0);
    (S[1] => CO[5]) = (0:0:0, 0:0:0);
    (S[1] => CO[6]) = (0:0:0, 0:0:0);
    (S[1] => CO[7]) = (0:0:0, 0:0:0);
    (S[1] => O[1]) = (0:0:0, 0:0:0);
    (S[1] => O[2]) = (0:0:0, 0:0:0);
    (S[1] => O[3]) = (0:0:0, 0:0:0);
    (S[1] => O[4]) = (0:0:0, 0:0:0);
    (S[1] => O[5]) = (0:0:0, 0:0:0);
    (S[1] => O[6]) = (0:0:0, 0:0:0);
    (S[1] => O[7]) = (0:0:0, 0:0:0);
    (S[2] => CO[2]) = (0:0:0, 0:0:0);
    (S[2] => CO[3]) = (0:0:0, 0:0:0);
    (S[2] => CO[4]) = (0:0:0, 0:0:0);
    (S[2] => CO[5]) = (0:0:0, 0:0:0);
    (S[2] => CO[6]) = (0:0:0, 0:0:0);
    (S[2] => CO[7]) = (0:0:0, 0:0:0);
    (S[2] => O[2]) = (0:0:0, 0:0:0);
    (S[2] => O[3]) = (0:0:0, 0:0:0);
    (S[2] => O[4]) = (0:0:0, 0:0:0);
    (S[2] => O[5]) = (0:0:0, 0:0:0);
    (S[2] => O[6]) = (0:0:0, 0:0:0);
    (S[2] => O[7]) = (0:0:0, 0:0:0);
    (S[3] => CO[3]) = (0:0:0, 0:0:0);
    (S[3] => CO[4]) = (0:0:0, 0:0:0);
    (S[3] => CO[5]) = (0:0:0, 0:0:0);
    (S[3] => CO[6]) = (0:0:0, 0:0:0);
    (S[3] => CO[7]) = (0:0:0, 0:0:0);
    (S[3] => O[3]) = (0:0:0, 0:0:0);
    (S[3] => O[4]) = (0:0:0, 0:0:0);
    (S[3] => O[5]) = (0:0:0, 0:0:0);
    (S[3] => O[6]) = (0:0:0, 0:0:0);
    (S[3] => O[7]) = (0:0:0, 0:0:0);
    (S[4] => CO[4]) = (0:0:0, 0:0:0);
    (S[4] => CO[5]) = (0:0:0, 0:0:0);
    (S[4] => CO[6]) = (0:0:0, 0:0:0);
    (S[4] => CO[7]) = (0:0:0, 0:0:0);
    (S[4] => O[4]) = (0:0:0, 0:0:0);
    (S[4] => O[5]) = (0:0:0, 0:0:0);
    (S[4] => O[6]) = (0:0:0, 0:0:0);
    (S[4] => O[7]) = (0:0:0, 0:0:0);
    (S[5] => CO[5]) = (0:0:0, 0:0:0);
    (S[5] => CO[6]) = (0:0:0, 0:0:0);
    (S[5] => CO[7]) = (0:0:0, 0:0:0);
    (S[5] => O[5]) = (0:0:0, 0:0:0);
    (S[5] => O[6]) = (0:0:0, 0:0:0);
    (S[5] => O[7]) = (0:0:0, 0:0:0);
    (S[6] => CO[6]) = (0:0:0, 0:0:0);
    (S[6] => CO[7]) = (0:0:0, 0:0:0);
    (S[6] => O[6]) = (0:0:0, 0:0:0);
    (S[6] => O[7]) = (0:0:0, 0:0:0);
    (S[7] => CO[7]) = (0:0:0, 0:0:0);
    (S[7] => O[7]) = (0:0:0, 0:0:0);
    specparam PATHPULSE$ = 0;
  endspecify

endmodule

`endcelldefine
