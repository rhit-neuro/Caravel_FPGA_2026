# Floating-point profiling on the KR260

*2026-10-21. Simulation: 23 designs, all pass. Vivado: 23 designs × 6 clock frequencies on `xck26-sfvc784-2LV-c`. Fixed-point results are in `DSP_Profiling_Results.md`.*

## How to read this

- Formats: half = 16-bit IEEE float, single = 32-bit IEEE float.
- Add, multiply and divide use AMD's Floating-Point IP (add and multiply set to use DSPs; the divider never uses them). 
- "Current design" = the synaptic module's own `FloatingAddition`, `FloatingMultiplication` and `LUT_MAC_Module`.

## Summary

| Operation | Hardware | Fastest single result | Highest clock |
|---|---|---|---|
| Add, half | 2 DSP, ~135 LUT | 10 ns (1 stage, 100 MHz) | 600 MHz with 11 stages (18 ns) |
| Add, single | 2 DSP, ~250 LUT | 10 ns (1 stage, 100 MHz) | 600 MHz with 11 stages (18 ns) |
| Multiply, half | 2 DSP, ~45 LUT | 10 ns (1 stage at 100 MHz, or 4 at 400) | 600 MHz with 8 stages (13 ns) |
| Multiply, single | 3 DSP, ~80 LUT | 7.5 ns (3 stages, 400 MHz) | 600 MHz with 6 stages (10 ns) |
| Divide, half | ~215 LUT | 16 ns (8 stages, 500 MHz) | 600 MHz with 15 stages (25 ns) |
| Divide, single | ~755 LUT | 47 ns (14 stages at 300 MHz, or 28 at 600) | 600 MHz with 28 stages (47 ns) |
| Power x^5, single | 3 DSP, ~130 LUT | 57 ns (6-stage multiplier, 600 MHz) | 600 MHz |
| Current design add | 508 LUT | 10 ns (100 MHz) | 100 MHz |
| Current design multiply | 2 DSP, 104 LUT | 10 ns (100 MHz) | 100 MHz |
| Current design multiply-add | 2 DSP, 596 LUT | ~11 ns (about 94 MHz) | fails at 100 MHz |

"Fastest single result" is the lowest latency across all tested configurations. A pipelined unit at its highest clock gives the most results per second (one per cycle), but each individual result takes longer.

## Cycles at each clock

A cell lists the stage options that pass at that clock, as their cycle counts. For example, `6, 11` means the 6- and 11-stage versions pass and the 1-stage version doesn't. ❌ = no option passes.

| Operation | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|
| Add, half (1 / 6 / 11 stages) | 1, 6, 11 | 6, 11 | 6, 11 | 11 | 11 | 11 |
| Add, single (1 / 6 / 11 stages) | 1, 6, 11 | 6, 11 | 6, 11 | 11 | 11 | 11 |
| Multiply, half (1 / 4 / 8 stages) | 1, 4, 8 | 4, 8 | 4, 8 | 4, 8 | 8 | 8 |
| Multiply, single (1 / 3 / 6 stages) | 1, 3, 6 | 3, 6 | 3, 6 | 3, 6 | 6 | 6 |
| Divide, half (1 / 8 / 15 stages) | 8, 15 | 8, 15 | 8, 15 | 8, 15 | 8, 15 | 15 |
| Divide, single (1 / 14 / 28 stages) | 14, 28 | 14, 28 | 14, 28 | 28 | 28 | 28 |
| Power x^5, single (1- / 6-stage multiplier) | 14, 34 | 14, 34 | 34 | 34 | 34 | 34 |
| Current design add, single | 1 | ❌ | ❌ | ❌ | ❌ | ❌ |
| Current design multiply, single | 1 | ❌ | ❌ | ❌ | ❌ | ❌ |
| Current design multiply-add, single | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

- Power x^n with an L-stage multiplier takes 2 + (n−1) × (L + 2) cycles. The table shows n = 5.
- To turn cycles into time, multiply by the clock period: 10 ns at 100 MHz, 5 ns at 200, 3.3 ns at 300, 2.5 ns at 400, 2 ns at 500, 1.7 ns at 600.

## Takeaways

- **Float costs much more than fixed point.** A 1-cycle fixed-point add or multiply uses 1 DSP and no LUTs and passes at 600 MHz. A 1-cycle float add uses 2 DSPs plus 135–275 LUTs and only passes at 100 MHz. Float needs 6–11 stages to match fixed point's clock speeds.
- **For float, pipeline stages decide the clock.** Unlike fixed point, a 1-stage float unit only reaches 100 MHz (multiply, add) or doesn't pass at all (divide). The maximum stage count reaches 600 MHz for every operation.
- **Division is the most expensive:** no DSPs, 755 LUTs at single precision, and at least 47 ns per result.
- **The current synaptic design's float units are limited to about 100 MHz.** Its multiply-add (`LUT_MAC_Module`) fails at 100 MHz (about 10.7 ns path). The h/g accumulators chain two of these in one cycle, so their path is roughly twice as long (an estimate; not built). That's fine at today's 12 MHz clock (83 ns), but raising the clock would need pipelining, or the IP above.

## Appendix: timing margins

Margin = time left over in each clock cycle (ns). Positive = passes; below about 0.1 ns = right at the limit.

| Design | Uses | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Add half, 1 stage | 2 DSP, 141 LUT | ✅ +2.21 | ❌ −2.03 | ❌ −3.88 | ❌ −4.73 | ❌ −5.10 | ❌ −5.54 |
| Add half, 6 stages | 2 DSP, 131 LUT | ✅ +4.24 | ✅ +1.51 | ✅ +0.01 | ❌ −0.85 | ❌ −1.46 | ❌ −1.72 |
| Add half, 11 stages | 2 DSP, 134 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Add single, 1 stage | 2 DSP, 275 LUT | ✅ +1.20 | ❌ −2.67 | ❌ −4.34 | ❌ −5.18 | ❌ −5.60 | ❌ −6.14 |
| Add single, 6 stages | 2 DSP, 251 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.38 | ❌ −0.08 | ❌ −0.56 | ❌ −0.97 |
| Add single, 11 stages | 2 DSP, 234 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply half, 1 stage | 2 DSP, 31 LUT | ✅ +4.25 | ❌ −0.46 | ❌ −2.14 | ❌ −2.98 | ❌ −3.41 | ❌ −3.82 |
| Multiply half, 4 stages | 2 DSP, 47 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.28 | ❌ −0.16 | ❌ −0.55 |
| Multiply half, 8 stages | 2 DSP, 48 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply single, 1 stage | 3 DSP, 84 LUT | ✅ +4.46 | ❌ −0.02 | ❌ −1.49 | ❌ −2.37 | ❌ −2.87 | ❌ −3.13 |
| Multiply single, 3 stages | 3 DSP, 85 LUT | ✅ +4.72 | ✅ +2.23 | ✅ +0.93 | ✅ +0.21 | ❌ −0.27 | ❌ −0.60 |
| Multiply single, 6 stages | 3 DSP, 78 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Divide half, 1 stage | 212 LUT | ❌ −1.49 | ❌ −7.08 | ❌ −8.33 | ❌ −9.88 | ❌ −9.62 | ❌ −9.65 |
| Divide half, 8 stages | 212 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.42 | ✅ +0.04 | ❌ −0.44 |
| Divide half, 15 stages | 217 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Divide single, 1 stage | 745 LUT | ❌ −20.48 | ❌ −25.89 | ❌ −27.25 | ❌ −26.89 | ❌ −27.33 | ❌ −27.62 |
| Divide single, 14 stages | 757 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.57 | ❌ −0.04 | ❌ −0.56 | ❌ −0.86 |
| Divide single, 28 stages | 755 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Power single, 1-stage multiplier | 3 DSP, 135 LUT | ✅ +4.30 | ✅ +0.06 | ❌ −1.52 | ❌ −2.41 | ❌ −2.83 | ❌ −3.27 |
| Power single, 6-stage multiplier | 3 DSP, 129 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Current design add | 508 LUT | ✅ +1.41 | ❌ −0.53 | ❌ −2.57 | ❌ −3.15 | ❌ −3.63 | ❌ −3.93 |
| Current design multiply | 2 DSP, 104 LUT | ✅ +2.95 | ❌ −0.44 | ❌ −2.19 | ❌ −2.99 | ❌ −3.33 | ❌ −3.84 |
| Current design multiply-add | 2 DSP, 596 LUT | ❌ −0.68 | ❌ −6.30 | ❌ −8.22 | ❌ −8.79 | ❌ −9.35 | ❌ −9.68 |

## Files and how to re-run

All in `floating_point/`:

| File | What it is |
|---|---|
| `rtl/float_ip_unit.v` | AMD Floating-Point IP (add / multiply / divide) behind a simple interface |
| `rtl/float_power.v` | x^n by repeated float multiplies |
| `rtl/current_design_float_unit.v` | The synaptic module's own float units, with an output register |
| `rtl/current_design/*.v` | Unchanged copies of `FloatingAddition`, `FloatingMultiplication`, `LUT_MAC_Module`, `Priority_Encoder` |
| `rtl/float_timing_harness.v` | Register wrapper used only for the timing builds |
| `tb/tb_float_profile.sv` | Counts cycles and checks answers for one configuration |
| `vivado/float_designs.tcl` | The list of designs and IP settings |
| `vivado/run_float_simulation.tcl` | Simulates every design (Vivado simulator); output in `float_sim_results.txt` |
| `vivado/run_float_profile.tcl` | Timing builds; output in `results_float_*.csv` |
| `vivado/make_float_tables.py` | Builds the tables above from the CSV files |

From `floating_point/vivado`:
```
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_float_simulation.tcl
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_float_profile.tcl -tclargs 100 200 300 400 500 600
python make_float_tables.py
```
Add design-name prefixes (for example `divide`) to either script to run only some designs.
