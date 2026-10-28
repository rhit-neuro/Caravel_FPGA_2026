# Profiling summary: cycles and best clock

KR260 (`xck26-sfvc784-2LV-c`, Vivado 2023.2).
- Fixed-point formats: 16-bit = Q4.12, 18-bit = Q2.16, 32-bit = Q16.16. Float: half = 16-bit IEEE, single = 32-bit IEEE.
- Best clock = highest clock that passes timing. Many pass with under 0.1 ns margin; plan one step lower.

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
| Reciprocal 1/x, 18-bit, NR 9-bit seed + 1 iteration (2) | 10 | 500 MHz |
| Reciprocal 1/x, 32-bit, NR 8-bit seed + 2 iterations (3) | 18 | 200 MHz |

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
| Reciprocal 1/x, single, NR 7-bit seed + 2 iterations (3) | 14 | 500 MHz |
| Current design add, single (1) | 1 | 100 MHz |
| Current design multiply, single (1) | 1 | 100 MHz |
| Current design multiply-add, single (1) | 1 | fails at 100 MHz (~94 MHz) |

## Memory reads

| Memory (stages) | Cycles | Best clock |
|---|---|---|
| BRAM read (1) | 1 | 500 MHz |
| URAM read (2) | 2 | 500 MHz |
| DDR4 single read, 16 B | 50 | 300 MHz |
| DDR4 burst read, 256 B | 66 | 300 MHz |

DDR4 reads vary: the slowest single read took 157 cycles, about 3× the average.

## Memory writes

| Memory (stages) | Cycles | Best clock |
|---|---|---|
| BRAM write (1) | 1 | 500 MHz |
| URAM write (1) | 1 | 500 MHz |
| DDR4 single write, 16 B | 28 | 300 MHz |
| DDR4 burst write, 256 B | 49 | 300 MHz |

## LUT: new design vs. current design

| | Current (32 breakpoints) | New (FP32, 64 entries, interpolation) |
|---|---:|---:|
| Max error | 1.4e-2 | 1.4e-3 |
| LUTs | 2,318 | 86 |
| DSPs | 2 | 1 |
| Cycles | 1 | 6 |
| Max clock | ~66 MHz | 600 MHz |

## Recommendations

- Use fixed point (Q2.16) wherever the value range allows. If the datapath stays in float, use the pipelined Floating-Point IP instead of the current units.
- Replace division with a Newton-Raphson reciprocal and a multiply.
- Use the new LUT design (FP32 input, 64 entries, interpolation, LUTRAM).
- For the 13 gating functions of the leech model, use one LUT pipeline that steps through 13 tables: 1 BRAM, 1 DSP, about 19 cycles for all 13 (estimate, not built).

## Detailed reports

- DSP and memory: `DSP_Profiling_Results.md`, `Floating_Point_Profiling_Results.md`, `Reciprocal_Profiling_Results.md`
- LUT: `LUTProfiling/LUT_Summary.md`, `LUT_Profiling_Results.md`
