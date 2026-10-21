# How long math operations take on the KR260's DSPs

*2026-10-20. All results below come from simulation (23 tests, all passing) and from Vivado builds on the KR260's FPGA (5 designs, no errors).*

## Summary

At the synaptic module's 12 MHz clock:

| Operation | Clock cycles | Time | Hardware used |
|---|---|---|---|
| Addition (18-bit or 32-bit) | **1** | 83 ns | 1 DSP |
| 18x18 fixed-point multiply | **1** | 83 ns | 1 DSP |
| 16x16 fixed-point multiply | **1** | 83 ns | 1 DSP |
| x^n by shift-and-add | **2 + (n-1) × 18** | x^5: 74 cycles = 6.2 µs | 1 DSP + 207 LUTs |

What this means:
1. **Add and multiply each take 1 clock cycle.** The DSP finishes the math in under 3 ns, and a 12 MHz clock cycle is 83 ns long. You can't go faster than 1 cycle at this clock, and there is no reason to add extra registers.
2. **18x18 costs the same as 16x16.** One DSP handles both, so 18-bit numbers give you more precision for free.
3. **The adder's width doesn't matter.** One DSP adds numbers up to 48 bits wide, so 18-bit and 32-bit additions cost the same.
4. **Shift-and-add power is slow.** It spends 18 cycles on each multiply. Using the 1-cycle DSP multiplier instead, x^5 would take about 4–5 cycles rather than 74. That is an estimate; it was not built or simulated.

## The clock: 12 MHz

The synaptic module would run on the Caravel 12 MHz clock:
- The board's 100 MHz clock goes into `clk_fix`, a clock divider that outputs 12 MHz (`CARVEL.xdc`, `caravel.v` line 96).
- Caravel's PLL is bypassed by default (`pll_bypass = 1`), so the user-project clocks (`wb_clk_i`, `user_clock2`) are that same 12 MHz.

Notes:
- `SynapticModule` is currently commented out of `TopLevel.v`.
- Its standalone testbenches use faster clocks (100 MHz and 500 MHz), but those exist only in simulation.

One 12 MHz clock cycle = **83.333 ns**.

## How cycles were measured

1. The testbench puts the two numbers on the module's inputs.
2. The next rising clock edge captures them (edge 1).
3. The testbench counts edges until the module's `output_valid` (or `done`) signal goes high.

"1 cycle" means the answer is ready right after the next clock edge. Every answer was also checked against the expected value.

## Number formats

The fixed-point name "Qm.f" means m integer bits (including the sign) and f bits after the binary point.
- **Q2.16** (18 bits): range -2 to +2, precision about 0.000015.
- **Q4.12** (16 bits): range -8 to +8, precision about 0.00024.
- **Q16.16** (32 bits): range about ±32768. Used only for the 32-bit adder, to match the current synaptic module's 32-bit word size.

Results are truncated (the extra low bits are dropped), not rounded. That is why 0.1 × 0.2 shows 0.01999 instead of 0.02000: 0.1 can't be stored exactly in binary.

## 1. Addition

The DSP's adder is 48 bits wide, so any size up to 48 bits takes one DSP and one cycle.

**18-bit (Q2.16)**: the same format as the 18x18 multiply results.

| a | b | a + b | Cycles |
|---|---|---|---|
| 0.75 | 0.5 | 1.25 | 1 |
| -1.25 | 0.375 | -0.875 | 1 |
| 1.125 | -1.9 | -0.775 | 1 |
| 0.0001 | 0.0002 | 0.0003 | 1 |

**32-bit (Q16.16)**: the same word size as the current synaptic module.

| a | b | a + b | Cycles |
|---|---|---|---|
| 1.5 | 2.25 | 3.75 | 1 |
| -3.75 | 1.25 | -2.5 | 1 |
| 100.5 | -0.125 | 100.375 | 1 |
| ~0 | -1234.5 | -1234.5 | 1 |

## 2. 18x18 fixed-point multiply (Q2.16)

| a | b | Result | Exact answer | Cycles |
|---|---|---|---|---|
| 1.5 | 0.75 | 1.12500 | 1.12500 | 1 |
| -1.25 | 1.5 | -1.87500 | -1.87500 | 1 |
| 0.1 | 0.2 | 0.01999 | 0.02000 | 1 |
| -0.5 | -0.5 | 0.25000 | 0.25000 | 1 |

## 3. 16x16 fixed-point multiply (Q4.12)

| a | b | Result | Exact answer | Cycles |
|---|---|---|---|---|
| 3.5 | 2.25 | 7.8750 | 7.8750 | 1 |
| -2.5 | 1.75 | -4.3750 | -4.3750 | 1 |
| 0.1 | 0.2 | 0.0198 | 0.0200 | 1 |
| -1.0 | -7.5 | 7.5000 | 7.5000 | 1 |

## 4. x^n by shift-and-add (Q2.16)

How it works:
- x^n is computed as x × x × ... × x, which is n − 1 multiplies.
- Each multiply uses shift-and-add instead of the DSP multiplier. For each of the 18 bits of x, one per clock cycle: if the bit is 1, add the shifted number to a running sum, then shift the number left by one.
- The running-sum addition happens in a DSP.

**Cycles = 2 + (n − 1) × 18** (2 cycles when n is 0 or 1). The extra 2 cycles are one to load the inputs and one to apply the sign at the end.

| x | n | Result | Exact answer | Cycles | Time at 12 MHz |
|---|---|---|---|---|---|
| 0.75 | 0 | 1.00000 | 1.00000 | 2 | 0.17 µs |
| 0.75 | 1 | 0.75000 | 0.75000 | 2 | 0.17 µs |
| 1.25 | 2 | 1.56250 | 1.56250 | 20 | 1.67 µs |
| -1.2 | 3 | -1.72797 | -1.72799 | 38 | 3.17 µs |
| 0.9 | 4 | 0.65607 | 0.65608 | 56 | 4.67 µs |
| 1.1 | 5 | 1.61040 | 1.61044 | 74 | 6.17 µs |
| 0.5 | 8 | 0.00391 | 0.00391 | 128 | 10.67 µs |

Limit: in Q2.16 the answer must stay between -2 and +2. If it goes outside that range it wraps around. For example, 1.5² = 2.25 comes out as -1.75.

## Vivado build results

Part: `xck26-sfvc784-2LV-c` (the Kria K26 module on the KR260). Timing target: 83.333 ns (12 MHz).

**Slack** is how much of the 83.333 ns clock period is left over after the slowest signal path finishes. Positive slack means the design works at 12 MHz.

| Design | DSPs | LUTs | Flip-flops* | Slack at 12 MHz | DSP registers used |
|---|---|---|---|---|---|
| Add, 18-bit | 1 | 0 | 57 | +81.3 ns | output only |
| Add, 32-bit | 1 | 0 | 99 | +81.6 ns | output only |
| Multiply 18x18 | 1 | 0 | 57 | +80.7 ns | output only |
| Multiply 16x16 | 1 | 0 | 51 | +80.9 ns | output only |
| Power, shift-and-add | 1 | 207 | 177 | +80.5 ns | input registers** |

\* Most of these flip-flops belong to the test wrapper (`timing_harness.v`), which surrounds each design with registers so Vivado can time it. The add and multiply designs themselves only use the DSP's output register and one `output_valid` flip-flop.

\*\* For the power unit, Vivado placed the running-sum registers inside the DSP's input registers. The control logic (state machine, shifting, bit counter, sign handling) is the 207 LUTs and 177 flip-flops in the regular FPGA fabric.

The add and multiply designs finish their math with about 81 ns to spare out of 83 ns. They use one DSP each and no other logic.

## Files

All paths are relative to the `DSP_Profiling` folder. The timing reports and Vivado log are not stored in git (the repo's `.gitignore` excludes `*.rpt` and `*.log`); running `run_profile.tcl` creates them again.

| File | What it is |
|---|---|
| `rtl/dsp_adder.v` | Adder in one DSP. Setting: `DATA_WIDTH`. |
| `rtl/dsp_fixed_point_multiplier.v` | Fixed-point multiplier in one DSP. Settings: `DATA_WIDTH`, `FRACTION_BITS`. |
| `rtl/shift_add_power.v` | x^n using shift-and-add. Settings: `DATA_WIDTH`, `FRACTION_BITS`, `EXPONENT_WIDTH`. |
| `rtl/timing_harness.v` | Register wrapper used only for the Vivado builds. |
| `tb/tb_dsp_profile.v` | 12 MHz testbench that counts cycles and checks answers. |
| `tb/sim_results.txt` | Output of the last simulation run. |
| `vivado/run_profile.tcl` | Script that builds all 5 designs in Vivado. |
| `vivado/results.csv` | Vivado results table. |
| `vivado/timing_<design>.rpt` | Slowest timing path for each design. |

**Re-run the simulation** (from the `DSP_Profiling` folder):
```
iverilog -g2012 -o tb/simulation.vvp tb/tb_dsp_profile.v rtl/dsp_adder.v rtl/dsp_fixed_point_multiplier.v rtl/shift_add_power.v
vvp -n tb/simulation.vvp
```

**Re-run the Vivado builds** (from the `DSP_Profiling\vivado` folder):
```
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_profile.tcl
```
