# FP32 operation timing on the KR260

Measures how long 32-bit floating-point add, multiply, shift and exponential (plus BRAM, URAM and DDR4 reads) take on the Kria K26 chip (`xck26-sfvc784-2LV-c`), and at which clock speeds they still work. Every result below comes from a full Vivado 2023.2 build (synthesis, placement, routing) and timing simulation at each clock.

> **🤖 AI disclosure:** The RTL, testbench, scripts, debugging and this write-up were produced with support from **Claude (Anthropic) in Claude Code**, Oct 20–21, 2026. `sim/xsim_fix/CARRY8.v` is AMD's CARRY8 model modified with Claude Opus 5.5.

## Summary

| Operation | Cycles | Fastest clock that passes | Time at that clock | Hardware (at 400 MHz) |
|---|---|---|---|---|
| Add a + b | 9 | 500 MHz | 18 ns | 541 LUTs, 405 FFs |
| Multiply a × b | 8 | 500 MHz | 16 ns | 2 DSPs, 125 LUTs, 208 FFs |
| Shift a × 2^k | 1 | 500 MHz | 2 ns | 48 LUTs, 33 FFs |
| Exponential e^a | 24 | 400 MHz | 60 ns | 12 DSPs, 449 LUTs, 378 FFs |
| BRAM read | 2 | 500 MHz | 4 ns | 1 BRAM |
| URAM read | 3 | 500 MHz | 6 ns | 1 URAM |
| DDR4 read | 46 (fake memory model) | – | – | needs the board |

**All seven units together pass up to 400 MHz.** exp is the slowest unit (estimated max ≈ 493 MHz), so it sets the clock.

## Cycles at each clock

Cycle counts are measured by the testbench and do not change with the clock. ❌ = fails at that clock.

| Operation | 12 MHz | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Add | 9 | 9 | 9 | 9 | 9 | 9 | ❌ |
| Multiply | 8 | 8 | 8 | 8 | 8 | 8 | ❌ |
| Shift | 1 | 1 | 1 | 1 | 1 | 1 | ❌ |
| Exponential | 24 | 24 | 24 | 24 | 24 | ❌ | ❌ |
| BRAM read | 2 | 2 | 2 | 2 | 2 | 2 | ❌ |
| URAM read | 3 | 3 | 3 | 3 | 3 | 3 | ❌ |
| DDR4 read (fake model) | 46 | 46 | 46 | 46 | 46 | 46 | 46 |

To turn cycles into time, multiply by the clock period: 83.3 ns at 12 MHz, 10 ns at 100, 5 ns at 200, 3.3 ns at 300, 2.5 ns at 400, 2 ns at 500, 1.7 ns at 600.

## How a unit passes

A unit PASSES at a clock only if all of these hold:

1. **Static timing (Vivado STA)** checks every path in the routed design: setup slack ≥ 0, hold slack ≥ 0, pulse width ≥ 0.
2. **Timing simulation, slow corner:** the same testbench runs on the routed netlist with the *slowest* delays a K26 chip is allowed to have (hot, low voltage). This catches signals that arrive **too late** for the next clock edge (setup problems), which is what limits the clock speed.
3. **Timing simulation, fast corner:** same run with the *fastest* allowed delays. This catches signals that change **too early**, before a register has finished capturing the old value (hold problems).

Any real chip falls between the two corners, so passing both means it works on whichever chip is on the board. Each run checks 3,040 add/multiply/shift/exp problems (isolated and back-to-back), 64 BRAM/URAM reads and 3 DDR4 reads, and requires every answer to be correct with a constant latency.

## What fails and why

- **500 MHz:** only exp fails. Static timing misses by 0.028 ns, although both simulations still got every answer right (simulation only tries some inputs; STA checks every path, so STA decides).
- **600 MHz:** everything except the DDR4 reader fails. Add, multiply, exp and URAM miss setup. BRAM and URAM are clocked faster than the memory blocks allow (pulse width −0.293 / −0.333 ns). The slow-corner simulation got multiply 20, shift 886 and exp 1,426 answers wrong out of 3,040.
- **Open question at 600 MHz:** shift passes static timing by only 0.023 ns but fails the slow-corner simulation. Two of its output bits (y[27], y[22]) receive the new value about 20–30 ps after the clock edge. Possibly the SDF delay file the simulation uses is slightly less exact than STA; not investigated further, since 600 MHz fails anyway.
- **Hold is never a problem:** the fast-corner simulation passed everywhere and hold slack is +0.05 ns or more at every clock.

## Takeaways

- **Plan for 400 MHz** with these pipelines. exp sets the limit (0.32 ns setup margin at 400 MHz).
- **Shift is nearly free:** 1 cycle, no DSPs, because a float shift is just an add on the 8-bit exponent.
- **exp is the most expensive unit:** 24 cycles and 12 DSPs. Another pipeline stage in exp, or stronger Vivado optimization settings, would be needed to reach 500 MHz.
- **DDR4 needs the board.** The 46 cycles come from a made-up memory model and only show that the AXI reader works. Real DDR4 numbers are in `../DSP_Profiling_Results.md` (measured on the KR260).

## Files

```
FP32_Sims/
  rtl/                     <- hardware (Vivado Design Sources)
    fp_timing_top.v        parent module; start reading here (Verilog-for-C cheat sheet)
    fp_add.v               float a + b          9 cycles
    fp_mul.v               float a * b          8 cycles, 2 DSPs
    fp_shift.v             float a * 2^k        1 cycle
    fp_exp.v               float e^a            24 cycles
    fp_exp2_rom.v          lookup table for fp_exp (generated)
    pipe_mult.v            pipelined multiplier helper (DSP slices)
    delay_line.v           "delay a signal N cycles" helper
    bram_test.v            Block RAM, 2-cycle read
    uram_test.v            UltraRAM, 3-cycle read
    ddr4_read_timer.v      AXI read of DDR4 with a cycle counter
  sim/                     <- simulation only (Vivado Simulation Sources)
    tb_fp_timing_top.v     testbench: measures latency, checks every answer
    axi_mem_model.v        fake DDR4 for simulation (delay is made up)
    xsim_fix/CARRY8.v      corrected copy of AMD's CARRY8 model (see below)
  scripts/
    gen_exp_rom.py         rebuilds fp_exp2_rom.v
    run_timing_sweep.tcl   RTL sim, then per frequency: build, timing analysis,
                           timing simulation (slow + fast corners) -> reports/
  reports/
    summary.md             one table per frequency (generated by the sweep)
    timing_sweep.csv       every number, one row per (frequency, unit), incl. LUT/FF/DSP/BRAM/URAM
    clk_<f>MHz.xdc         clock constraint used at each frequency
```

## How to run

From this folder, in the Vivado Tcl Shell (or call `vivado.bat` by its full path):

```
vivado -mode batch -source scripts/run_timing_sweep.tcl
```

The full sweep (7 clocks) takes about 2 hours and needs about 4 GB of free RAM; close browsers first. To run only some clocks, set `FP_FREQS` first (e.g. `set FP_FREQS=12 100` on Windows). Then read `reports/summary.md`. The simulation folders it creates (`reports/sim_*`, ~90 MB each) are git-ignored.

## Notes on the Windows / xsim fixes

- **Command files:** on Windows the simulator tools (xvlog, xelab, xsim) are `.bat` files, and cmd splits arguments at `=`, so `-d CLK_PS=83333` arrived as two words and every timing simulation failed with `XSIM 43-4316`. The script now writes the options to a file and calls `xvlog -f` / `xelab -f`.
- **CARRY8 model:** with that fixed, add got 4 of 3,040 answers wrong even at 12 MHz with 80 ns of slack, while the zero-delay netlist was correct. AMD's simulation model of the CARRY8 carry-chain cell computes its sum by reading back its own delayed output port, and xsim 2023.2 left a stale value on the output. `sim/xsim_fix/CARRY8.v` computes the carry on internal wires instead; ports, logic and all pin-to-pin delays are unchanged. The script compiles it into its own library and puts it ahead of AMD's for timing simulation only. With it, both corners give 3,040/3,040 wherever static timing passes.
- **DSP count:** now counts physical DSP48E2 blocks (multiply = 2, previously over-counted as 18).

## Version history

- **v1 (10/20):** add 5, mul 4, shift 1, exp 10 cycles. The 10/21 sweep showed the clock limits were add/mul ~300 MHz and exp ~250 MHz. Hold failures came from the pin paths, and latency was typed into the script instead of measured.
- **v2 (10/21):**
  - Deeper pipelines: add 9, mul 8, exp 24 cycles.
  - Boundary registers on the top module, with pin paths excluded from timing.
  - The testbench measures latency and counts wrong, X and missing answers. It runs isolated operations, then back-to-back traffic.
  - The sweep adds per-unit hold and pulse-width checks, plus SDF timing simulation at slow and fast corners.
  - Fixed the LUT count query.
- **v2.1 (10/21):** Windows command-file fix, CARRY8 simulation fix, DSP count fix, wrong-answer messages print time and cycle. First complete sweep with timing simulation (results above).

## Appendix: timing margins (setup slack, ns)

| Unit | 12 MHz | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Add | ✅ +80.80 | ✅ +7.47 | ✅ +2.53 | ✅ +1.25 | ✅ +0.37 | ✅ +0.24 | ❌ −0.015 |
| Multiply | ✅ +80.88 | ✅ +7.63 | ✅ +2.54 | ✅ +1.29 | ✅ +0.61 | ✅ +0.14 | ❌ −0.030 |
| Shift | ✅ +80.39 | ✅ +7.37 | ✅ +2.28 | ✅ +1.28 | ✅ +0.57 | ✅ +0.21 | ❌ +0.023 (sim fails) |
| Exponential | ✅ +80.38 | ✅ +7.25 | ✅ +2.12 | ✅ +0.80 | ✅ +0.32 | ❌ −0.028 | ❌ −0.361 |
| BRAM read | ✅ +82.16 | ✅ +8.77 | ✅ +3.83 | ✅ +2.12 | ✅ +1.29 | ✅ +0.87 | ❌ pulse −0.293 |
| URAM read | ✅ +81.42 | ✅ +8.09 | ✅ +3.09 | ✅ +1.35 | ✅ +0.58 | ✅ +0.19 | ❌ −0.020, pulse −0.333 |
| DDR4 read | ✅ +80.06 | ✅ +7.10 | ✅ +2.47 | ✅ +1.09 | ✅ +0.63 | ✅ +0.39 | ✅ +0.063 |

Hold and pulse-width margins for every unit and clock are in `reports/summary.md` and `reports/timing_sweep.csv`.
