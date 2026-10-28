# Profiling summary: cycles and best clock

Compiled from `DSP_Profiling_Results.md`, `Floating_Point_Profiling_Results.md`, `Reciprocal_Profiling_Results.md` and `LUTProfiling/LUT_Summary.md`. All results are for the KR260 (`xck26-sfvc784-2LV-c`, Vivado 2023.2). Every design was checked in simulation, then placed and routed at 100–600 MHz. DDR4 timing was measured on the board itself.
- Fixed-point formats: 16-bit = Q4.12, 18-bit = Q2.16, 32-bit = Q16.16. Float: half = 16-bit IEEE, single = 32-bit IEEE.
- "Best clock" = the highest clock that passes timing. Many designs pass it with under 0.1 ns of margin, so plan a full design one clock step lower.
- Number in brackets = pipeline stages.

## Fixed point

| Operation (stages) | Cycles | Best clock |
|---|---|---|
| Add, 18-bit (1) | 1 | 600 MHz |
| Add, 32-bit (1) | 1 | 600 MHz |
| Multiply 16x16 (1) | 1 | 600 MHz |
| Multiply 18x18 (1) | 1 | 600 MHz |
| Multiply 32x32 (1) | 1 | 300 MHz |
| Divide, 16-bit (iterative) | 30 | 400 MHz |
| Divide, 18-bit (iterative) | 36 | 400 MHz |
| Divide, 32-bit (iterative) | 50 | 400 MHz |
| Power x^5, 18-bit (iterative) | 74 | 400 MHz |
| Power x^5, 32-bit (iterative) | 130 | 600 MHz |
| Reciprocal 1/x, 16-bit, NR 8-bit seed + 1 iteration (2) | 10 | 400 MHz |
| Reciprocal 1/x, 18-bit, NR 9-bit seed + 1 iteration (2) | 10 | 500 MHz (400 MHz with more margin) |
| Reciprocal 1/x, 32-bit, NR 8-bit seed + 2 iterations (3) | 18 | 200 MHz |

- Add and multiply up to 18 bits use 1 DSP. 32x32 multiply uses 4 DSPs; extra stages don't raise its clock.
- Reciprocal rows are the recommended (big seed table) designs. The small-seed versions (4-bit seed + 2 iterations, 3 stages) reach one step higher, 16-bit at 500 MHz and 18-bit at 600 MHz, but take 18 cycles, twice the DSPs, and pass with only 0.00–0.01 ns of margin.
- Reciprocal + multiply replaces division: 10 cycles against 30–36, and it takes a new input every cycle (the divider is busy for the whole division).

## Floating point

| Operation (stages) | Cycles | Best clock |
|---|---|---|
| Add, half (11) | 11 | 600 MHz |
| Add, single (11) | 11 | 600 MHz |
| Multiply, half (8) | 8 | 600 MHz |
| Multiply, single (6) | 6 | 600 MHz |
| Divide, half (15) | 15 | 600 MHz |
| Divide, single (28) | 28 | 600 MHz |
| Power x^5, single (6-stage multiplier) | 34 | 600 MHz |
| Reciprocal 1/x, half, IP (1) | 1 | 600 MHz |
| Reciprocal 1/x, single, IP (29) | 29 | 600 MHz |
| Reciprocal 1/x, single, NR 7-bit seed + 2 iterations (3) | 14 | 500 MHz (400 MHz with more margin) |
| Current design add, single (1) | 1 | 100 MHz |
| Current design multiply, single (1) | 1 | 100 MHz |
| Current design multiply-add, single (1) | 1 | fails at 100 MHz (~94 MHz) |

- Add, multiply, divide and the IP reciprocal use AMD's Floating-Point IP. With 1 stage, float add and multiply only reach 100 MHz and divide doesn't pass at all; they need 6–28 stages to match fixed point's clock.
- For single-precision 1/x, Newton-Raphson takes half the cycles of the IP (14 against 29) but tops out at 500 MHz.
- The current synaptic design's float units are limited to about 100 MHz. That's fine at today's 12 MHz clock, but a faster clock needs pipelining or the IP.

## Memory reads

| Memory (stages) | Cycles | Best clock |
|---|---|---|
| BRAM read (1) | 1 | 500 MHz |
| URAM read (2) | 2 | 500 MHz |
| DDR4 single read, 16 B | 50 | 300 MHz |
| DDR4 burst read, 256 B | 66 | 300 MHz |

## Memory writes

| Memory (stages) | Cycles | Best clock |
|---|---|---|
| BRAM write (1) | 1 | 500 MHz |
| URAM write (1) | 1 | 500 MHz |
| DDR4 single write, 16 B | 28 | 300 MHz |
| DDR4 burst write, 256 B | 49 | 300 MHz |

- URAM with 1 read stage reaches 400 MHz; 2 or more reach 500 MHz.
- DDR4 cycles are averages at 300 MHz, the highest clock the Zynq HP0 port allows (about 333 MHz): 165 ns per single read, 92 ns per single write. Reads vary a lot: the slowest single read took 157 cycles (523 ns), about 3× the average. On-chip memory (2–4 ns) is roughly 25–100× faster.

## LUT: new design vs. current design

The LUT approximates the synaptic function f(x) = 1 / (1 + 2·e^(180(x+0.049)) + e^(500(x+0.049))).

- **Current design:** compares the input against all 32 breakpoints in parallel to find its segment.
- **New design:** reads the table address directly from bits of the input, then interpolates between two neighbouring entries.

| | Current (32 breakpoints) | New (FP32, 64 entries, interpolation) |
|---|---:|---:|
| Max error | 1.4e-2 | **1.4e-3** (10× lower) |
| LUTs | 2,318 | **86** (27× fewer) |
| DSPs | 2 | **1** |
| Cycles | 1 | 6 |
| Max clock | ~66 MHz | **600 MHz** |
| Time per result | ~15 ns | **10 ns** |
| Results per second | ~66 M | **600 M** |

The current design scales badly: 128 breakpoints take 6,268 LUTs and drop the clock to about 56 MHz. Its only advantage is that breakpoints can be placed anywhere, while the new design needs evenly spaced entries.

## Recommendations

- **Use fixed point (Q2.16) wherever the value range allows.** If the datapath stays in float, use the pipelined Floating-Point IP instead of the current units.
- **Replace division with a Newton-Raphson reciprocal and a multiply.**
- **Use the new LUT design** (FP32 input, 64 entries, interpolation, LUTRAM).
- **For the 13 gating functions of the leech model**, use one LUT pipeline that steps through 13 tables. All 13 fit in one block RAM, need 1 DSP, and give 13 results in about 19 cycles (about 38 ns at 500 MHz, the BRAM limit). This is an estimate; it hasn't been built yet.

## Detailed reports

- **DSP and memory:** `DSP_Profiling_Results.md`, `Floating_Point_Profiling_Results.md`, `Reciprocal_Profiling_Results.md`
- **LUT:** `LUTProfiling/LUT_Summary.md`, `LUT_Profiling_Results.md`
