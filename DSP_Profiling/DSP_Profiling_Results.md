# DSP, memory and DDR profiling on the KR260

- Number formats: 16-bit = Q4.12, 18-bit = Q2.16, 32-bit = Q16.16.

## Summary

| Operation | Cycles | Fastest clock that passes | Time at that clock | Hardware |
|---|---|---|---|---|
| Add, 18 or 32-bit | 1 (or 2 with 2 stages) | 600 MHz | 1.7 ns | 1 DSP |
| Multiply 16x16 or 18x18 | 1 (up to 4 with more stages) | 600 MHz | 1.7 ns | 1 DSP |
| Multiply 32x32 | 1 (up to 4 with more stages) | 300 MHz | 3.3 ns | 4 DSPs |
| Divide 16 / 18 / 32-bit | 30 / 36 / 50 | 400 MHz | 75 / 90 / 125 ns | 1 DSP + 130–274 LUTs |
| Power x^n, 18-bit | 2 + (n−1) × 18 | 400 MHz | x^5: 185 ns | 1 DSP + 207 LUTs |
| Power x^n, 32-bit | 2 + (n−1) × 32 | 600 MHz | x^5: 217 ns | 296 LUTs |
| BRAM write / read | 1 / 1 (2 with 2 stages) | 500 MHz | 2 ns | 1 BRAM |
| URAM write / read | 1 / 1 (2–3 with more stages) | 400 MHz with 1 stage, 500 MHz with 2+ | 2.5–4 ns | 1 URAM |
| DDR4 single read / write | ~50 / ~28 at 300 MHz | 300 MHz (port limit) | 165 / 92 ns | Zynq DDR controller |

## Cycles at each clock

| Operation | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|
| Add 18-bit (1–2 stages) | 1–2 | 1–2 | 1–2 | 1–2 | 1–2 | 1–2 |
| Add 32-bit (1–2 stages) | 1–2 | 1–2 | 1–2 | 1–2 | 1–2 | 1–2 |
| Multiply 16x16 (1–4 stages) | 1–4 | 1–4 | 1–4 | 1–4 | 1–4 | 1–4 |
| Multiply 18x18 (1–4 stages) | 1–4 | 1–4 | 1–4 | 1–4 | 1–4 | 1–4 |
| Multiply 32x32 (1–4 stages) | 1–4 | 1–4 | 1–4 | ❌ | ❌ | ❌ |
| Divide 16-bit | 30 | 30 | 30 | 30 | ❌ | ❌ |
| Divide 18-bit | 36 | 36 | 36 | 36 | ❌ | ❌ |
| Divide 32-bit | 50 | 50 | 50 | 50 | ❌ | ❌ |
| Power x^5 18-bit | 74 | 74 | 74 | 74 | ❌ | ❌ |
| Power x^5 32-bit | 130 | 130 | 130 | 130 | 130 | 130 |
| BRAM write | 1 | 1 | 1 | 1 | 1 | ❌ |
| BRAM read (1–2 stages) | 1–2 | 1–2 | 1–2 | 1–2 | 1–2 | ❌ |
| URAM write | 1 | 1 | 1 | 1 | 1 | ❌ |
| URAM read (1–3 stages) | 1–3 | 1–3 | 1–3 | 1–3 | 2–3 | ❌ |
| DDR4 single write (16 B) | 14 | 21 | 28 | – | – | – |
| DDR4 single read (16 B) | 20 | 34 | 50 | – | – | – |
| DDR4 burst write (256 B) | 32 | 41 | 49 | – | – | – |
| DDR4 burst read (256 B) | 35 | 52 | 66 | – | – | – |

To turn cycles into time, multiply by the clock period: 10 ns at 100 MHz, 5 ns at 200, 3.3 ns at 300, 2.5 ns at 400, 2 ns at 500, 1.7 ns at 600.

## DDR4 (measured on the board)

DDR4 is the only entry whose cycle count changes with the clock. The DDR runs at its own fixed speed, so a faster FPGA clock fits more of its cycles into the same wait. The FPGA reaches the DDR through the Zynq's HP0 port (128-bit AXI, max about 333 MHz). 

| Test | 100 MHz | 200 MHz | 300 MHz |
|---|---|---|---|
| Single write (16 B) | 141 ns | 105 ns | 92 ns |
| Single read (16 B) | 195 ns | 168 ns | 165 ns |
| Burst write (256 B) | 320 ns | 205 ns | 164 ns |
| Burst read (256 B) | 350 ns | 257 ns | 219 ns |

These are averages. Reads vary a lot: the slowest single read took 157 cycles at 300 MHz (523 ns), about 3× the average. Min/max values are in `vivado/ddr_results_<f>MHz.csv`.

## Takeaways

- **Add and multiply (up to 18 bits) are 1 cycle and pass up to 600 MHz.** At 600 MHz the margin is under 0.1 ns, so plan for 500 MHz or less in a full design. Extra stages aren't needed.
- **32-bit multiply is the exception:** it needs 4 DSPs and tops out at 300 MHz. Extra stages don't help here, because they sit before and after the multiply, not between the 4 DSPs.
- **Division and power are slow** (tens of cycles) because they handle one bit per cycle.
- **On-chip memory is roughly 40–100× faster than DDR4:** 2–4 ns for BRAM/URAM against 92–195 ns for DDR4, and DDR4 timing varies.
- **URAM is the only case where stages decide the clock:** 1 stage reaches 400 MHz, 2 or 3 stages reach 500 MHz.

## Appendix: timing margins

### 16/18-bit operations

| Design | Uses | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Add 18-bit, 1 stage | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.90 | ✅ +0.48 | ✅ +0.09 |
| Add 18-bit, 2 stages | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.97 | ✅ +0.72 | ✅ +0.56 |
| Multiply 18x18, 1 stage | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +0.90 | ✅ +0.20 | ✅ +0.38 | ✅ +0.04 |
| Multiply 18x18, 2 stages | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +1.36 | ✅ +0.53 | ✅ +0.03 | ✅ +0.04 |
| Multiply 18x18, 3 stages | 1 DSP | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply 18x18, 4 stages | 1 DSP | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply 16x16, 1 stage | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +0.94 | ✅ +0.24 | ✅ +0.37 | ✅ +0.05 |
| Multiply 16x16, 2 stages | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +1.36 | ✅ +0.53 | ✅ +0.03 | ✅ +0.05 |
| Multiply 16x16, 3 stages | 1 DSP | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply 16x16, 4 stages | 1 DSP | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Power 18-bit | 1 DSP, 207 LUT | ✅ +4.72 | ✅ +2.23 | ✅ +0.52 | ✅ +0.11 | ❌ −0.24 | ❌ −0.46 |
| Divide 16-bit | 1 DSP, 130 LUT | ✅ +4.72 | ✅ +1.75 | ✅ +0.36 | ✅ +0.27 | ❌ −0.31 | ❌ −0.53 |
| Divide 18-bit | 1 DSP, 159 LUT | ✅ +4.72 | ✅ +1.80 | ✅ +0.34 | ✅ +0.23 | ❌ −0.12 | ❌ −0.49 |

### 32-bit operations

| Design | Uses | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Add 32-bit, 1 stage | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.97 | ✅ +0.51 | ✅ +0.22 |
| Add 32-bit, 2 stages | 1 DSP | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.97 | ✅ +0.72 | ✅ +0.56 |
| Multiply 32x32, 1 stage | 4 DSP, 31 LUT | ✅ +4.72 | ✅ +1.59 | ✅ +0.17 | ❌ −0.74 | ❌ −1.24 | ❌ −1.54 |
| Multiply 32x32, 2 stages | 4 DSP, 31 LUT | ✅ +4.72 | ✅ +2.11 | ✅ +0.44 | ❌ −0.39 | ❌ −0.89 | ❌ −1.22 |
| Multiply 32x32, 3 stages | 4 DSP, 31 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.44 | ❌ −0.39 | ❌ −0.89 | ❌ −1.22 |
| Multiply 32x32, 4 stages | 4 DSP, 31 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.44 | ❌ −0.39 | ❌ −0.89 | ❌ −1.22 |
| Power 32-bit | 296 LUT | ✅ +4.72 | ✅ +2.23 | ✅ +0.91 | ✅ +0.52 | ✅ +0.23 | ✅ +0.01 |
| Divide 32-bit | 1 DSP, 274 LUT | ✅ +4.72 | ✅ +1.44 | ✅ +0.34 | ✅ +0.17 | ❌ −0.34 | ❌ −0.64 |

### Memories

| Design | Uses | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| BRAM read, 1 stage | 1 BRAM | ✅ +4.42 | ✅ +1.92 | ✅ +1.09 | ✅ +0.54 | ✅ +0.04 | ❌ −0.29 |
| BRAM read, 2 stages | 1 BRAM | ✅ +4.42 | ✅ +1.92 | ✅ +1.09 | ✅ +0.54 | ✅ +0.04 | ❌ −0.29 |
| URAM read, 1 stage | 1 URAM | ✅ +4.20 | ✅ +1.70 | ✅ +0.86 | ✅ +0.03 | ❌ −0.47 | ❌ −0.80 |
| URAM read, 2 stages | 1 URAM | ✅ +4.20 | ✅ +1.70 | ✅ +0.87 | ✅ +0.45 | ✅ +0.00 | ❌ −0.33 |
| URAM read, 3 stages | 1 URAM | ✅ +4.20 | ✅ +1.70 | ✅ +0.87 | ✅ +0.45 | ✅ +0.00 | ❌ −0.33 |

## Files and how to re-run

| File | What it is |
|---|---|
| `rtl/dsp_adder.v` | Adder in one DSP (1–2 stages) |
| `rtl/dsp_fixed_point_multiplier.v` | Fixed-point multiplier in DSPs (1–4 stages) |
| `rtl/shift_subtract_divider.v` | Fixed-point division, one bit per cycle |
| `rtl/shift_add_power.v` | x^n using shift-and-add |
| `rtl/bram_memory.v` | 1024 × 18 block RAM (1–2 read stages) |
| `rtl/uram_memory.v` | 4096 × 72 UltraRAM (1–3 read stages) |
| `rtl/ddr_latency_tester.v` | Times DDR reads/writes through the Zynq HP0 port |
| `rtl/timing_harness.v` | Register wrapper used only for the timing builds |
| `tb/tb_dsp_profile.v` | Counts cycles and checks answers for every operation |
| `tb/tb_ddr_latency_tester.v` | Checks the DDR tester against a fixed-delay memory model |
| `vivado/run_profile.tcl` | Timing builds at the frequencies given |
| `vivado/make_results_tables.py` | Builds the tables above from the result CSV files |
| `vivado/build_ddr_tester.tcl` | Builds the DDR tester bitstream for one frequency |
| `vivado/load_bitstream_uboot.py` | Sends a bitstream to U-Boot over serial and programs the FPGA |
| `vivado/run_ddr_test.tcl` | Runs the DDR test over JTAG and saves the results |

**Simulation** (from `DSP_Profiling`):
```
iverilog -g2012 -o tb/simulation.vvp tb/tb_dsp_profile.v rtl/dsp_adder.v rtl/dsp_fixed_point_multiplier.v rtl/shift_add_power.v rtl/shift_subtract_divider.v rtl/bram_memory.v rtl/uram_memory.v
vvp -n tb/simulation.vvp
```

**Timing builds** (from `DSP_Profiling/vivado`; add name prefixes such as `uram` to build only some designs):
```
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_profile.tcl -tclargs 100 200 300 400 500 600
python make_results_tables.py
```

**DDR test on the board** (board at the U-Boot `ZynqMP>` prompt, serial on COM11):
1. `vivado.bat -mode batch -source build_ddr_tester.tcl -tclargs 200`
2. In U-Boot: `dcache off`, then `mw.l 0x40000000 0x0 0x8000` (clears the test area)
3. `python load_bitstream_uboot.py ddr_tester_200MHz.bit COM11` (programs the FPGA through U-Boot, which also powers up the FPGA fabric)
4. `vivado.bat -mode batch -source run_ddr_test.tcl -tclargs 200`

Don't read PMU registers (`0xFFD8xxxx`) from U-Boot: that crashes U-Boot and the board needs a reset.
