# FP32 operation timing sweep on the KR260 (xck26-sfvc784-2LV-c)

Latency is measured by the testbench in timing simulation. Slack is from Vivado static timing (negative = violation). A unit PASSES at a frequency only if setup, hold and pulse width all meet timing AND both timing simulations (slow/max and fast/min delays) returned every answer correctly with constant latency.

## 12 MHz (83.333 ns)

Design-wide: setup WNS 80.055 ns, hold WHS 0.051 ns, pulse-width WPWS 40.867 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 750.0 ns | 3040/3040 / 3040/3040 | 80.804 / 0.094 / 40.904 | 395.4 MHz | PASS |
| multiply | 8 cycles / 666.66 ns | 3040/3040 / 3040/3040 | 80.879 / 0.059 / 40.904 | 407.5 MHz | PASS |
| shift | 1 cycles / 83.33 ns | 3040/3040 / 3040/3040 | 80.394 / 0.063 / 41.391 | 340.3 MHz | PASS |
| exp | 24 cycles / 1999.99 ns | 3040/3040 / 3040/3040 | 80.381 / 0.068 / 40.904 | 338.8 MHz | PASS |
| bram_read | 2 cycles / 166.67 ns | 64/64 / 64/64 | 82.164 / 0.085 / 41.089 | 855.4 MHz | PASS |
| uram_read | 3 cycles / 250.0 ns | 64/64 / 64/64 | 81.419 / 0.051 / 40.866 | 522.5 MHz | PASS |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 80.055 / 0.055 / 41.391 | 305.1 MHz | PASS |

## 100 MHz (10.000 ns)

Design-wide: setup WNS 7.103 ns, hold WHS 0.051 ns, pulse-width WPWS 4.200 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 90.0 ns | 3040/3040 / 3040/3040 | 7.468 / 0.092 / 4.238 | 394.9 MHz | PASS |
| multiply | 8 cycles / 80.0 ns | 3040/3040 / 3040/3040 | 7.631 / 0.063 / 4.238 | 422.1 MHz | PASS |
| shift | 1 cycles / 10.0 ns | 3040/3040 / 3040/3040 | 7.368 / 0.063 / 4.725 | 379.9 MHz | PASS |
| exp | 24 cycles / 240.0 ns | 3040/3040 / 3040/3040 | 7.25 / 0.068 / 4.238 | 363.6 MHz | PASS |
| bram_read | 2 cycles / 20.0 ns | 64/64 / 64/64 | 8.773 / 0.085 / 4.423 | 815.0 MHz | PASS |
| uram_read | 3 cycles / 30.0 ns | 64/64 / 64/64 | 8.086 / 0.051 / 4.200 | 522.5 MHz | PASS |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 7.103 / 0.055 / 4.725 | 345.2 MHz | PASS |

## 200 MHz (5.000 ns)

Design-wide: setup WNS 2.122 ns, hold WHS 0.055 ns, pulse-width WPWS 1.700 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 45.0 ns | 3040/3040 / 3040/3040 | 2.532 / 0.075 / 1.738 | 405.2 MHz | PASS |
| multiply | 8 cycles / 40.0 ns | 3040/3040 / 3040/3040 | 2.542 / 0.059 / 1.738 | 406.8 MHz | PASS |
| shift | 1 cycles / 5.0 ns | 3040/3040 / 3040/3040 | 2.278 / 0.063 / 2.225 | 367.4 MHz | PASS |
| exp | 24 cycles / 120.0 ns | 3040/3040 / 3040/3040 | 2.122 / 0.068 / 1.738 | 347.5 MHz | PASS |
| bram_read | 2 cycles / 10.0 ns | 64/64 / 64/64 | 3.831 / 0.085 / 1.923 | 855.4 MHz | PASS |
| uram_read | 3 cycles / 15.0 ns | 64/64 / 64/64 | 3.086 / 0.064 / 1.700 | 522.5 MHz | PASS |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 2.472 / 0.055 / 2.225 | 395.6 MHz | PASS |

## 300 MHz (3.333 ns)

Design-wide: setup WNS 0.798 ns, hold WHS 0.055 ns, pulse-width WPWS 0.866 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 30.0 ns | 3040/3040 / 3040/3040 | 1.253 / 0.072 / 0.904 | 480.8 MHz | PASS |
| multiply | 8 cycles / 26.66 ns | 3040/3040 / 3040/3040 | 1.288 / 0.069 / 0.904 | 489.0 MHz | PASS |
| shift | 1 cycles / 3.33 ns | 3040/3040 / 3040/3040 | 1.277 / 0.063 / 1.391 | 486.4 MHz | PASS |
| exp | 24 cycles / 79.99 ns | 3040/3040 / 3040/3040 | 0.798 / 0.058 / 0.904 | 394.5 MHz | PASS |
| bram_read | 2 cycles / 6.67 ns | 64/64 / 64/64 | 2.119 / 0.087 / 1.089 | 823.7 MHz | PASS |
| uram_read | 3 cycles / 10.0 ns | 64/64 / 64/64 | 1.351 / 0.075 / 0.866 | 504.5 MHz | PASS |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 1.094 / 0.055 / 1.391 | 446.6 MHz | PASS |

## 400 MHz (2.500 ns)

Design-wide: setup WNS 0.318 ns, hold WHS 0.049 ns, pulse-width WPWS 0.450 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 22.5 ns | 3040/3040 / 3040/3040 | 0.37 / 0.062 / 0.488 | 469.5 MHz | PASS |
| multiply | 8 cycles / 20.0 ns | 3040/3040 / 3040/3040 | 0.606 / 0.059 / 0.488 | 528.0 MHz | PASS |
| shift | 1 cycles / 2.5 ns | 3040/3040 / 3040/3040 | 0.567 / 0.073 / 0.975 | 517.3 MHz | PASS |
| exp | 24 cycles / 60.0 ns | 3040/3040 / 3040/3040 | 0.318 / 0.06 / 0.488 | 458.3 MHz | PASS |
| bram_read | 2 cycles / 5.0 ns | 64/64 / 64/64 | 1.291 / 0.082 / 0.540 | 827.1 MHz | PASS |
| uram_read | 3 cycles / 7.5 ns | 64/64 / 64/64 | 0.582 / 0.049 / 0.450 | 521.4 MHz | PASS |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 0.632 / 0.055 / 0.975 | 535.3 MHz | PASS |

## 500 MHz (2.000 ns)

Design-wide: setup WNS -0.028 ns, hold WHS 0.055 ns, pulse-width WPWS 0.000 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 18.0 ns | 3040/3040 / 3040/3040 | 0.24 / 0.064 / 0.238 | 568.2 MHz | PASS |
| multiply | 8 cycles / 16.0 ns | 3040/3040 / 3040/3040 | 0.142 / 0.061 / 0.238 | 538.2 MHz | PASS |
| shift | 1 cycles / 2.0 ns | 3040/3040 / 3040/3040 | 0.214 / 0.073 / 0.725 | 559.9 MHz | PASS |
| exp | 24 cycles / 48.0 ns | 3040/3040 / 3040/3040 | -0.028 / 0.065 / 0.238 | 493.1 MHz | FAIL |
| bram_read | 2 cycles / 4.0 ns | 64/64 / 64/64 | 0.867 / 0.09 / 0.040 | 882.6 MHz | PASS |
| uram_read | 3 cycles / 6.0 ns | 64/64 / 64/64 | 0.188 / 0.067 / 0.000 | 551.9 MHz | PASS |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 0.392 / 0.055 / 0.725 | 621.9 MHz | PASS |

## 600 MHz (1.667 ns)

Design-wide: setup WNS -0.361 ns, hold WHS 0.047 ns, pulse-width WPWS -0.333 ns

| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |
| --- | --- | --- | --- | --- | --- |
| add | 9 cycles / 15.0 ns | 3040/3040 / 3040/3040 | -0.015 / 0.085 / 0.072 | 594.5 MHz | FAIL |
| multiply | 8 cycles / 13.34 ns | 3020/3040 / 3040/3040 | -0.03 / 0.063 / 0.072 | 589.3 MHz | FAIL |
| shift | 1 cycles / 1.67 ns | 2154/3040 / 3040/3040 | 0.023 / 0.063 / 0.559 | 608.3 MHz | FAIL |
| exp | 24 cycles / 40.01 ns | 1614/3040 / 3040/3040 | -0.361 / 0.064 / 0.072 | 493.1 MHz | FAIL |
| bram_read | 2 cycles / 3.33 ns | 64/64 / 64/64 | 0.555 / 0.068 / -0.293 | 899.3 MHz | FAIL |
| uram_read | 3 cycles / 5.0 ns | 64/64 / 64/64 | -0.02 / 0.047 / -0.333 | 592.8 MHz | FAIL |
| ddr4_read | 46 cycles / fake model ns | 3/3 / 3/3 | 0.063 / 0.055 / 0.559 | 623.4 MHz | PASS |

Resource counts per unit (LUT, FF, SRL, DSP, BRAM, URAM) are in timing_sweep.csv.
DDR4 latency comes from a fake memory model; real DDR4 latency needs the board.
