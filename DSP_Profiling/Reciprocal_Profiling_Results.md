# Reciprocal 1/x on the KR260 (Newton-Raphson)

*2026-10-22. Fixed point: 18 designs × 6 clock frequencies. Floating point: 18 designs (12 Newton-Raphson, 6 AMD IP) × 6 clock frequencies. All on `xck26-sfvc784-2LV-c`; all simulations pass. Other operations are in `DSP_Profiling_Results.md` and `Floating_Point_Profiling_Results.md`.*

## How to read this

- Fixed-point formats: 16-bit = Q4.12, 18-bit = Q2.16, 32-bit = Q16.16. Float: half = 16-bit IEEE, single = 32-bit IEEE.
- "NR" = our Newton-Raphson design. "IP" = AMD's Floating-Point IP set to Reciprocal (float only).
- "Stages" = register stages per multiply inside NR (1–3), or the IP's pipeline stages.
- Every design is fully pipelined: it takes a new input every cycle. Cycles = from input to result.
- Margin = time left over in each clock cycle (ns). Below about 0.1 ns = right at the limit; plan a full design one clock step lower.

## Best options

| Format | Best option | Stages | Cycles | Clock (margin) | DSPs | Other |
|---|---|---|---|---|---|---|
| 16-bit | NR, 8-bit seed + 1 iteration | 2 | 10 | 400 MHz (+0.18 ns) | 2 | 1 BRAM, 206 LUTs |
| 18-bit | NR, 9-bit seed + 1 iteration | 2 | 10 | 400 MHz (+0.18 ns), or 500 MHz (+0.03 ns) | 2 | 1 BRAM, 267 LUTs |
| 32-bit | NR, 8-bit seed + 2 iterations | 3 | 18 | 200 MHz (+0.44 ns) | 11 | 1 BRAM, 467 LUTs |
| Half float | IP | 1 | 1 | 600 MHz (+0.32 ns) | 0 | 172 LUTs |
| Single float | NR, 7-bit seed + 2 iterations | 3 | 14 | 400 MHz (+0.30 ns), or 500 MHz (+0.03 ns) | 5 | 77 LUTs |

- **The big seed table always wins.** The small-table versions need more DSPs (2× for 16/18-bit and half, 1.4–1.6× for 32-bit and single) and more cycles for the same accuracy. Use them only if you run out of BRAMs (fixed point), or for the last clock step (16-bit at 500 MHz, 18-bit at 600 MHz), which they reach with almost no margin (0.00–0.01 ns).
- **1 stage gives the fewest cycles at low clocks:** 8 cycles up to 300 MHz (16/18-bit), 6 cycles at 200 MHz (single), 10 cycles at 100 MHz (32-bit).
- **32-bit is expensive:** 11 DSPs and at most 200 MHz. If the values fit in 18 bits, the 18-bit version gives the same 1-LSB accuracy with 2 DSPs.

## Accuracy

The accuracy depends only on the seed table and the number of iterations, not on the stages. Every setting was sized to reach full accuracy, so all versions of a format have the same bound.

| Format | Error (every input) | Exact | 1 LSB / 1 ulp | Inputs that fit |
|---|---|---|---|---|
| 16-bit Q4.12 | ≤ 1 LSB, always low | 99.25% equal the truncated exact value | 2⁻¹² ≈ 0.00024 | \|x\| > 0.125 |
| 18-bit Q2.16 | ≤ 1 LSB, always low | 95.9% | 2⁻¹⁶ ≈ 0.000015 | \|x\| > 0.5 |
| 32-bit Q16.16 | ≤ 1 LSB, always low | 100% of 200,000 sampled inputs | 2⁻¹⁶ ≈ 0.000015 | \|x\| > 2⁻¹⁵ |
| Half, NR | ≤ 1 ulp | 89.1% correctly rounded | ≤ 0.1% relative | all |
| Half, IP | ≤ 1 ulp | 93.3% correctly rounded | ≤ 0.1% relative | all |
| Single, NR | ≤ 1 ulp | 94.6% correctly rounded | ≤ 1.2×10⁻⁷ relative | all |
| Single, IP | ≤ 1 ulp | 97.1% correctly rounded | ≤ 1.2×10⁻⁷ relative | all |

- Fixed point: "truncated exact value" = the true 1/x with its extra bits dropped, the same rounding as the shift-subtract divider. Powers of two (1/1, 1/0.5, …) are always exact.
- Fixed point, out of range: the result saturates and the `overflow` output is set; 1/0 gives the largest positive value (like the divider). Q2.16 only holds values up to 2, so 1/x only fits for \|x\| > 0.5 (25% of all inputs saturate).
- Float: 1/±0 = ±infinity, 1/±infinity = ±0, NaN gives NaN, powers of two are exact. Subnormals count as zero (as in the IP).
- Checked in simulation: every 16- and 18-bit input on all 6 versions; 200,000 32-bit inputs; every half-precision bit pattern; 20,000 random single-precision ones.

## Cycles compared with division

Fewest cycles of any version that passes at each clock (❌ = none passes). Divider rows are from `DSP_Profiling_Results.md` (shift-subtract divider) and `Floating_Point_Profiling_Results.md` (IP divider).

**Fixed point**

| Format | Unit | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| 16-bit | Divider | 30 | 30 | 30 | 30 | ❌ | ❌ |
| | NR | 8 | 8 | 8 | 8 | 18 | ❌ |
| | Fewer cycles with NR | 3.8× | 3.8× | 3.8× | 3.8× | only NR passes | – |
| 18-bit | Divider | 36 | 36 | 36 | 36 | ❌ | ❌ |
| | NR | 8 | 8 | 8 | 10 | 10 | 18 |
| | Fewer cycles with NR | 4.5× | 4.5× | 4.5× | 3.6× | only NR passes | only NR passes |
| 32-bit | Divider | 50 | 50 | 50 | 50 | ❌ | ❌ |
| | NR | 10 | 18 | ❌ | ❌ | ❌ | ❌ |
| | Fewer cycles with NR | 5× | 2.8× | only divider passes | only divider passes | – | – |

**Floating point**

| Format | Unit | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Half | IP divider | 8 | 8 | 8 | 8 | 8 | 15 |
| | NR | 4 | 4 | 4 | 6 | 6 | 8 |
| | IP reciprocal | 1 | 1 | 1 | 1 | 1 | 1 |
| Single | IP divider | 14 | 14 | 14 | 28 | 28 | 28 |
| | NR | 6 | 6 | 14 | 14 | 14 | ❌ |
| | IP reciprocal | 15 | 15 | 15 | 29 | 29 | 29 |

The divider is also busy for every cycle of a fixed-point division (one result per 30–50 cycles), while NR takes a new input every cycle. The IP divider is pipelined too.

## How the Newton-Raphson design works

One core, `rtl/newton_raphson_core.v`, used by both the fixed-point and the float version. It finds y ≈ 1/d for 0.5 ≤ d < 1:
1. **Seed:** the top bits of d pick an entry of a small table, y₀ = 2/(a + b) for that interval [a, b) of d, good to about (seed bits + 1) bits.
2. **Iterations:** each one doubles the correct bits: `e = 1 − d·y`, then `y = y + y·e` (the usual y·(2 − d·y), rearranged so the second multiply only sees the small error e). Each is one multiply-subtract or multiply-add in a DSP (`rtl/nr_multiply_add.v`).
3. **Reduced width:** each iteration only works at the precision it can deliver, so early iterations are narrow and fit in one DSP. All steps round down.

Around the core:
- **Fixed point** (`rtl/newton_raphson_reciprocal.v`): take \|x\|, count leading zeros and shift to d, run the core, shift back, apply the sign, saturate. Cycles = 6 + 2 × iterations × stages.
- **Float** (`floating_point/rtl/float_newton_raphson_reciprocal.v`): floats are already normalized, so the mantissa goes straight in (d = 1.f / 2). The core's y becomes the new mantissa (rounded to nearest) and the exponent becomes 2·bias − 1 − E. No leading-zero count or shifter, so it needs far fewer LUTs (42–77 against 200–470). Cycles = 2 + 2 × iterations × stages.

**Settings swept** (each with 1, 2 and 3 stages per multiply). Seed sizes are the smallest that reach full accuracy (chosen with a bit-exact Python model).

| Format | Big seed table, fewer iterations | Small seed table, more iterations |
|---|---|---|
| 16-bit | 8-bit seed (256 entries) + 1 iteration: 2 DSP, 1 BRAM | 4-bit seed (16 entries) + 2 iterations: 4 DSP |
| 18-bit | 9-bit seed (512 entries) + 1 iteration: 2 DSP, 1 BRAM | 4-bit seed + 2 iterations: 4 DSP |
| 32-bit | 8-bit seed + 2 iterations: 11 DSP, 1 BRAM | 4-bit seed + 3 iterations: 15 DSP |
| Half | 7-bit seed (128 entries) + 1 iteration: 2 DSP | 3-bit seed + 2 iterations: 4 DSP |
| Single | 7-bit seed + 2 iterations: 5 DSP | 4-bit seed + 3 iterations: 8 DSP |

The fixed-point seed table goes in a BRAM; the float one fits in LUTs.

**What the stages change:** 1 stage reaches 300 MHz for 16/18-bit and half (16-bit: 400 MHz by 0.01 ns), 200 MHz for single and 100 MHz for 32-bit. More stages: 16-bit reaches 400 MHz (500 MHz with the small seed and 3 stages, +0.00 ns), 18-bit 500 MHz with 2 stages (600 MHz with the small seed and 3 stages, +0.01 ns), half 500 MHz with 2 stages and 600 MHz with 3, single 500 MHz (3 stages), 32-bit 200 MHz (3 stages). Wide multiplies limit the 32-bit and single versions: they need several DSPs, and the path between those DSPs isn't registered (a 4th stage was tried; Vivado didn't use it), the same limit as the 32x32 multiplier.

## Appendix: cycles and timing margins

### Fixed point: cycles at each clock

Cycle counts of the 1/2/3-stage versions that pass.

| Operation | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|
| Reciprocal 16-bit, 8-bit seed + 1 iteration (1–3 stages) | 8, 10, 12 | 8, 10, 12 | 8, 10, 12 | 8, 10, 12 | ❌ | ❌ |
| Reciprocal 16-bit, 4-bit seed + 2 iterations (1–3 stages) | 10, 14, 18 | 10, 14, 18 | 10, 14, 18 | 14, 18 | 18 | ❌ |
| Reciprocal 18-bit, 9-bit seed + 1 iteration (1–3 stages) | 8, 10, 12 | 8, 10, 12 | 8, 10, 12 | 10, 12 | 10, 12 | ❌ |
| Reciprocal 18-bit, 4-bit seed + 2 iterations (1–3 stages) | 10, 14, 18 | 10, 14, 18 | 10, 14, 18 | 14, 18 | 14, 18 | 18 |
| Reciprocal 32-bit, 8-bit seed + 2 iterations (1–3 stages) | 10, 14, 18 | 18 | ❌ | ❌ | ❌ | ❌ |
| Reciprocal 32-bit, 4-bit seed + 3 iterations (1–3 stages) | 12, 18, 24 | 24 | ❌ | ❌ | ❌ | ❌ |

### Fixed point: timing margins

| Design | Uses | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Reciprocal 16-bit, 8-bit seed + 1 iteration, 1 stage | 2 DSP, 1 BRAM, 206 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.63 | ✅ +0.01 | ❌ −0.48 | ❌ −0.84 |
| Reciprocal 16-bit, 8-bit seed + 1 iteration, 2 stages | 2 DSP, 1 BRAM, 206 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.77 | ✅ +0.18 | ❌ −0.12 | ❌ −0.44 |
| Reciprocal 16-bit, 8-bit seed + 1 iteration, 3 stages | 2 DSP, 1 BRAM, 206 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.77 | ✅ +0.17 | ❌ −0.18 | ❌ −0.36 |
| Reciprocal 16-bit, 4-bit seed + 2 iterations, 1 stage | 4 DSP, 204 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.48 | ❌ −0.21 | ❌ −0.68 | ❌ −1.02 |
| Reciprocal 16-bit, 4-bit seed + 2 iterations, 2 stages | 4 DSP, 204 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.87 | ✅ +0.33 | ❌ −0.06 | ❌ −0.42 |
| Reciprocal 16-bit, 4-bit seed + 2 iterations, 3 stages | 4 DSP, 204 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.76 | ✅ +0.31 | ✅ +0.00 | ❌ −0.31 |
| Reciprocal 18-bit, 9-bit seed + 1 iteration, 1 stage | 2 DSP, 1 BRAM, 267 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.68 | ❌ −0.11 | ❌ −0.48 | ❌ −0.81 |
| Reciprocal 18-bit, 9-bit seed + 1 iteration, 2 stages | 2 DSP, 1 BRAM, 267 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.87 | ✅ +0.18 | ✅ +0.03 | ❌ −0.30 |
| Reciprocal 18-bit, 9-bit seed + 1 iteration, 3 stages | 2 DSP, 1 BRAM, 267 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.85 | ✅ +0.38 | ✅ +0.06 | ❌ −0.11 |
| Reciprocal 18-bit, 4-bit seed + 2 iterations, 1 stage | 4 DSP, 274 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.39 | ❌ −0.10 | ❌ −0.69 | ❌ −0.97 |
| Reciprocal 18-bit, 4-bit seed + 2 iterations, 2 stages | 4 DSP, 274 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.86 | ✅ +0.40 | ✅ +0.03 | ❌ −0.30 |
| Reciprocal 18-bit, 4-bit seed + 2 iterations, 3 stages | 4 DSP, 274 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.76 | ✅ +0.33 | ✅ +0.20 | ✅ +0.01 |
| Reciprocal 32-bit, 8-bit seed + 2 iterations, 1 stage | 11 DSP, 1 BRAM, 467 LUT | ✅ +3.57 | ❌ −1.00 | ❌ −2.67 | ❌ −3.49 | ❌ −3.99 | ❌ −4.39 |
| Reciprocal 32-bit, 8-bit seed + 2 iterations, 2 stages | 11 DSP, 1 BRAM, 467 LUT | ✅ +4.24 | ❌ −0.24 | ❌ −1.92 | ❌ −2.73 | ❌ −3.24 | ❌ −3.57 |
| Reciprocal 32-bit, 8-bit seed + 2 iterations, 3 stages | 11 DSP, 1 BRAM, 467 LUT | ✅ +4.24 | ✅ +0.44 | ❌ −0.72 | ❌ −1.50 | ❌ −2.00 | ❌ −2.33 |
| Reciprocal 32-bit, 4-bit seed + 3 iterations, 1 stage | 15 DSP, 474 LUT | ✅ +3.57 | ❌ −1.01 | ❌ −2.49 | ❌ −3.54 | ❌ −3.91 | ❌ −4.34 |
| Reciprocal 32-bit, 4-bit seed + 3 iterations, 2 stages | 15 DSP, 474 LUT | ✅ +4.24 | ❌ −0.25 | ❌ −1.92 | ❌ −2.75 | ❌ −3.25 | ❌ −3.62 |
| Reciprocal 32-bit, 4-bit seed + 3 iterations, 3 stages | 15 DSP, 474 LUT | ✅ +4.24 | ✅ +0.61 | ❌ −0.67 | ❌ −1.50 | ❌ −2.00 | ❌ −2.33 |

### Floating point: cycles at each clock

| Operation | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|
| Reciprocal, half, IP (1 / 2 / 4 stages) | 1, 2, 4 | 1, 2, 4 | 1, 2, 4 | 1, 2, 4 | 1, 2, 4 | 1, 2 |
| Reciprocal, single, IP (1 / 15 / 29 stages) | 15, 29 | 15, 29 | 15, 29 | 29 | 29 | 29 |
| Reciprocal, half, NR 7-bit seed + 1 iteration (1 / 2 / 3 stages) | 4, 6, 8 | 4, 6, 8 | 4, 6, 8 | 6, 8 | 6, 8 | 8 |
| Reciprocal, half, NR 3-bit seed + 2 iterations (1 / 2 / 3 stages) | 6, 10, 14 | 6, 10, 14 | 6, 10, 14 | 10, 14 | 10, 14 | 14 |
| Reciprocal, single, NR 7-bit seed + 2 iterations (1 / 2 / 3 stages) | 6, 10, 14 | 6, 10, 14 | 14 | 14 | 14 | ❌ |
| Reciprocal, single, NR 4-bit seed + 3 iterations (1 / 2 / 3 stages) | 8, 14, 20 | 14, 20 | 20 | ❌ | ❌ | ❌ |

### Floating point: timing margins

| Design | Uses | 100 MHz | 200 MHz | 300 MHz | 400 MHz | 500 MHz | 600 MHz |
|---|---|---|---|---|---|---|---|
| Reciprocal half, IP, 1 stage | 172 LUT | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.83 | ✅ +0.41 | ✅ +0.32 |
| Reciprocal half, IP, 2 stages | 152 LUT | ✅ +4.72 | ✅ +2.23 | ✅ +1.39 | ✅ +0.71 | ✅ +0.45 | ✅ +0.26 |
| Reciprocal half, IP, 4 stages | 1 BRAM, 22 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ❌ −0.04 |
| Reciprocal single, IP, 1 stage | 8 DSP, 91 LUT | ❌ −9.90 | ❌ −15.19 | ❌ −16.68 | ❌ −17.56 | ❌ −18.37 | ❌ −18.45 |
| Reciprocal single, IP, 15 stages | 8 DSP, 77 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.66 | ❌ −0.07 | ❌ −0.48 | ❌ −0.88 |
| Reciprocal single, IP, 29 stages | 8 DSP, 77 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.07 |
| Reciprocal half, NR 7-bit seed + 1 iteration, 1 stage | 2 DSP, 56 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.70 | ❌ −0.13 | ❌ −0.63 | ❌ −0.96 |
| Reciprocal half, NR 7-bit seed + 1 iteration, 2 stages | 2 DSP, 56 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.03 | ❌ −0.30 |
| Reciprocal half, NR 7-bit seed + 1 iteration, 3 stages | 2 DSP, 56 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.05 |
| Reciprocal half, NR 3-bit seed + 2 iterations, 1 stage | 4 DSP, 42 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.62 | ❌ −0.12 | ❌ −0.62 | ❌ −0.95 |
| Reciprocal half, NR 3-bit seed + 2 iterations, 2 stages | 4 DSP, 42 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.03 | ❌ −0.30 |
| Reciprocal half, NR 3-bit seed + 2 iterations, 3 stages | 4 DSP, 42 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.90 | ✅ +0.49 | ✅ +0.24 | ✅ +0.04 |
| Reciprocal single, NR 7-bit seed + 2 iterations, 1 stage | 5 DSP, 77 LUT | ✅ +4.24 | ✅ +0.56 | ❌ −0.50 | ❌ −1.36 | ❌ −1.88 | ❌ −2.18 |
| Reciprocal single, NR 7-bit seed + 2 iterations, 2 stages | 5 DSP, 77 LUT | ✅ +4.24 | ✅ +1.31 | ❌ −0.23 | ❌ −1.07 | ❌ −1.57 | ❌ −1.90 |
| Reciprocal single, NR 7-bit seed + 2 iterations, 3 stages | 5 DSP, 77 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.83 | ✅ +0.30 | ✅ +0.03 | ❌ −0.30 |
| Reciprocal single, NR 4-bit seed + 3 iterations, 1 stage | 8 DSP, 63 LUT | ✅ +4.03 | ❌ −0.21 | ❌ −1.88 | ❌ −2.69 | ❌ −3.20 | ❌ −3.53 |
| Reciprocal single, NR 4-bit seed + 3 iterations, 2 stages | 8 DSP, 63 LUT | ✅ +4.24 | ✅ +0.46 | ❌ −1.16 | ❌ −2.01 | ❌ −2.51 | ❌ −2.83 |
| Reciprocal single, NR 4-bit seed + 3 iterations, 3 stages | 8 DSP, 63 LUT | ✅ +4.24 | ✅ +1.74 | ✅ +0.42 | ❌ −0.41 | ❌ −0.92 | ❌ −1.25 |

## Files and how to re-run

| File | What it is |
|---|---|
| `rtl/newton_raphson_core.v` | Seed table + Newton-Raphson iterations (shared) |
| `rtl/nr_multiply_add.v` | c ± a·b in a DSP (1–3 stages), used by the core |
| `rtl/newton_raphson_reciprocal.v` | Fixed-point 1/x: normalize, core, shift back, saturate |
| `floating_point/rtl/float_newton_raphson_reciprocal.v` | Float 1/x: unpack, core, round, pack |
| `floating_point/rtl/float_ip_unit.v` | AMD IP wrapper; `OPERANDS = 1` for the IP reciprocal |
| `tb/tb_dsp_profile.v` | Fixed-point testbench (section 9: reciprocal); output in `tb/sim_results.txt` |
| `floating_point/tb/tb_float_profile.sv` | Float testbench (codes 7 = IP reciprocal, 8 = NR); output in `floating_point/vivado/float_sim_results.txt` |
| `vivado/run_profile.tcl`, `floating_point/vivado/float_designs.tcl` | The reciprocal designs are the rows named `reciprocal…` |
| `vivado/make_results_tables.py`, `floating_point/vivado/make_float_tables.py` | Print the tables above (last, under "For Reciprocal_Profiling_Results.md") |

**Fixed point** (from `DSP_Profiling`): simulation is the command in `DSP_Profiling_Results.md` (about 6 minutes). Timing builds, from `vivado`:
```
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_profile.tcl -tclargs reciprocal 100 200 300 400 500 600
python make_results_tables.py
```

**Floating point** (from `floating_point/vivado`; run the build from a folder with a short path, see `Floating_Point_Profiling_Results.md`):
```
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_float_simulation.tcl -tclargs reciprocal
D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source <path>/run_float_profile.tcl -tclargs reciprocal 100 200 300 400 500 600
python make_float_tables.py
```

Each Vivado build process needs about 3.5 GB of RAM.
