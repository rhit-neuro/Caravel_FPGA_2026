"""
make_float_tables.py

Prints the Markdown tables for Floating_Point_Profiling_Results.md from the
results_float_*.csv files written by run_float_profile.tcl.

Usage (from this folder):  python make_float_tables.py
"""
import csv
import glob

FREQUENCIES = [100, 200, 300, 400, 500, 600]

# One row per operation: (label, [(design, cycles), ...]) -- one entry per
# pipeline-stage option. Cycles come from simulation (float_sim_results.txt).
# Power: x^5 with an L-stage multiplier takes 2 + 4 * (L + 2) cycles.
CYCLES = [
    ("Add, half (1 / 6 / 11 stages)", [("add_half_1", 1), ("add_half_6", 6), ("add_half_11", 11)]),
    ("Add, single (1 / 6 / 11 stages)", [("add_single_1", 1), ("add_single_6", 6), ("add_single_11", 11)]),
    ("Multiply, half (1 / 4 / 8 stages)", [("multiply_half_1", 1), ("multiply_half_4", 4), ("multiply_half_8", 8)]),
    ("Multiply, single (1 / 3 / 6 stages)", [("multiply_single_1", 1), ("multiply_single_3", 3), ("multiply_single_6", 6)]),
    ("Divide, half (1 / 8 / 15 stages)", [("divide_half_1", 1), ("divide_half_8", 8), ("divide_half_15", 15)]),
    ("Divide, single (1 / 14 / 28 stages)", [("divide_single_1", 1), ("divide_single_14", 14), ("divide_single_28", 28)]),
    ("Power x^5, single (1 / 6-stage multiplier)", [("power_single_1", 14), ("power_single_6", 34)]),
    ("Current design add, single", [("current_add_single", 1)]),
    ("Current design multiply, single", [("current_multiply_single", 1)]),
    ("Current design multiply-add, single", [("current_mac_single", 1)]),
]

results = {}
for path in glob.glob("results_float_*.csv"):
    for row in csv.DictReader(open(path)):
        results[(row["design"], int(row["frequency_mhz"]))] = row


def passes(design, frequency):
    row = results.get((design, frequency))
    return None if row is None else row["passes"] == "yes"


def cycles_cell(options, frequency):
    """Cycle counts of the stage options that pass, e.g. "6, 11"."""
    if any(passes(design, frequency) is None for design, _ in options):
        return "–"
    passing = [str(cycles) for design, cycles in options if passes(design, frequency)]
    return ", ".join(passing) if passing else "❌"


def margin_cell(design, frequency):
    row = results.get((design, frequency))
    if row is None:
        return "–"
    margin = min(float(row["setup_slack_ns"]), float(row["pulse_width_slack_ns"]))
    return ("✅" if row["passes"] == "yes" else "❌") + f" {margin:+.2f}"


def uses(design):
    row = results.get((design, 100))
    if row is None:
        return "–"
    parts = [f"{row['dsp_count']} DSP"] if row["dsp_count"] != "0" else []
    parts.append(f"{row['lut_count']} LUT")
    return ", ".join(parts)


header = " | ".join(f"{f} MHz" for f in FREQUENCIES)

print("### Clock cycles at each frequency\n")
print(f"| Operation | {header} |")
print("|---|" + "---|" * len(FREQUENCIES))
for label, options in CYCLES:
    print(f"| {label} | " + " | ".join(cycles_cell(options, f) for f in FREQUENCIES) + " |")

print("\n### Timing margins\n")
print(f"| Design | Uses | {header} |")
print("|---|---|" + "---|" * len(FREQUENCIES))
for label, options in CYCLES:
    for design, _ in options:
        print(f"| {design} | {uses(design)} | " + " | ".join(margin_cell(design, f) for f in FREQUENCIES) + " |")
