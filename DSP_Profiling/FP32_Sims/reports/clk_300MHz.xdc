create_clock -period 3.333 -name clk [get_ports clk]
# Pins sit behind boundary registers (fp_timing_top.v), which stand in for
# the neighbouring on-chip logic. Pin <-> register paths are not part of
# the measurement (out-of-context pins have no real location).
set_false_path -from [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_false_path -to   [get_ports -filter {DIRECTION == OUT}]
