# DSP and BRAM profiling on the KR260

*2026-10-20. Simulation: 16 tests, all pass. Vivado: 13 designs × 6 frequencies on `xck26-sfvc784-2LV-c`, no errors.*

## Clock cycles per operation

Cycle counts depend only on the number of pipeline stages, not on the clock frequency.

| Operation | 1 stage | 2 stages | 3 stages | 4 stages |
|---|---|---|---|---|
| Add (18-bit Q2.16) | 1 | 2 | – | – |
| Multiply 18x18 (Q2.16) | 1 | 2 | 3 | 4 |
| Multiply 16x16 (Q4.12) | 1 | 2 | 3 | 4 |
| BRAM write | 1 | – | – | – |
| BRAM read | 1 | 2 | – | – |
| Power x^n, shift-and-add | 2 + (n−1) × 18 (e.g. x^5 = 74) | – | – | – |

## Does it meet timing? (100–600 MHz)

✅ = passes, ❌ = fails. The number is the timing margin in ns (how much time is left over in the clock cycle). Below about 0.1 ns the design is right at the limit.

| Design | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|
| Add, 1 stage | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.90 | ✅ +0.48 | ✅ +0.09 |
| Add, 2 stages | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.97 | ✅ +0.72 | ✅ +0.56 |
| Multiply 18x18, 1 stage | ✅ +4.72 | ✅ +2.23 | ✅ +0.90 | ✅ +0.20 | ✅ +0.38 | ✅ +0.04 |
| Multiply 18x18, 2 stages | ✅ +4.72 | ✅ +2.23 | ✅ +1.36 | ✅ +0.53 | ✅ +0.03 | ✅ +0.04 |
| Multiply 18x18, 3 stages | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply 18x18, 4 stages | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply 16x16, 1 stage | ✅ +4.72 | ✅ +2.23 | ✅ +0.94 | ✅ +0.24 | ✅ +0.37 | ✅ +0.05 |
| Multiply 16x16, 2 stages | ✅ +4.72 | ✅ +2.23 | ✅ +1.36 | ✅ +0.53 | ✅ +0.03 | ✅ +0.05 |
| Multiply 16x16, 3 stages | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Multiply 16x16, 4 stages | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Power, shift-and-add | ✅ +4.72 | ✅ +2.23 | ✅ +0.52 | ✅ +0.11 | ❌ −0.24 | ❌ −0.46 |
| BRAM read, 1 stage | ✅ +4.42 | ✅ +1.92 | ✅ +1.09 | ✅ +0.54 | ✅ +0.04 | ❌ −0.29 |
| BRAM read, 2 stages | ✅ +4.42 | ✅ +1.92 | ✅ +1.09 | ✅ +0.54 | ✅ +0.04 | ❌ −0.29 |

Each design uses 1 DSP or 1 BRAM (RAMB18) and no other logic, except the power unit, which also needs 207 LUTs.

## Takeaways

- **The DSPs pass at every frequency up to 600 MHz, with any number of stages.** At 600 MHz the margin is below 0.1 ns for everything except the 2-stage add. That will likely fail once it sits inside a full design, so use 500 MHz or less for the multiplier.
- **Extra multiplier stages don't reliably buy speed.** At 500 MHz, 1 stage had more margin (+0.38 ns) than 2 stages (+0.03 ns). 3 and 4 stages are identical, capped by the DSP's own minimum clock period. 1 stage is enough up to 500 MHz.
- **BRAM tops out at 500 MHz.** At 600 MHz it fails because the clock is faster than the BRAM block itself allows, so the output register (2 stages) doesn't help.
- **Shift-and-add power tops out at 400 MHz** and is slow: x^5 = 74 cycles = 185 ns even at 400 MHz.

## Files

| File | What it is |
|---|---|
| `rtl/dsp_adder.v` | Adder in one DSP (`PIPELINE_STAGES` 1–2) |
| `rtl/dsp_fixed_point_multiplier.v` | Fixed-point multiplier in one DSP (`PIPELINE_STAGES` 1–4) |
| `rtl/bram_memory.v` | 1024 × 18 block RAM (`READ_PIPELINE_STAGES` 1–2) |
| `rtl/shift_add_power.v` | x^n using shift-and-add |
| `rtl/timing_harness.v` | Register wrapper used only for Vivado builds |
| `tb/tb_dsp_profile.v` | Testbench that counts cycles and checks answers |
| `tb/sim_results.txt` | Last simulation output |
| `vivado/run_profile.tcl` | Builds all designs at the frequencies given |
| `vivado/results_<f>MHz.csv` | Vivado results per frequency |

**Simulation** (from `DSP_Profiling`):
```
iverilog -g2012 -o tb/simulation.vvp tb/tb_dsp_profile.v rtl/dsp_adder.v rtl/dsp_fixed_point_multiplier.v rtl/shift_add_power.v rtl/bram_memory.v
vvp -n tb/simulation.vvp
```

**Vivado** (from `DSP_Profiling/vivado`; one process per frequency list):
```
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_profile.tcl -tclargs 100 200 300 400 500 600
```
