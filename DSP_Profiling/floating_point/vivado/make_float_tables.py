"""
make_float_tables.py

Prints the Markdown tables for Floating_Point_Profiling_Results.md from the
results_float_*.csv files written by run_float_profile.tcl. The reciprocal
tables (for Reciprocal_Profiling_Results.md) are printed last, under their own
heading.

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

# Reciprocal 1/x: the IP and our Newton-Raphson design (NR), for
# Reciprocal_Profiling_Results.md. NR: 2 + 2 * iterations * (stages per multiply) cycles.
RECIPROCAL_CYCLES = [
    ("Reciprocal, half, IP (1 / 2 / 4 stages)",
     [("reciprocal_ip_half_1", 1), ("reciprocal_ip_half_2", 2), ("reciprocal_ip_half_4", 4)]),
    ("Reciprocal, single, IP (1 / 15 / 29 stages)",
     [("reciprocal_ip_single_1", 1), ("reciprocal_ip_single_15", 15), ("reciprocal_ip_single_29", 29)]),
    ("Reciprocal, half, NR 7-bit seed + 1 iteration (1 / 2 / 3 stages)",
     [(f"reciprocal_nr_half_seed7_1iter_{n}", 2 + 2 * 1 * n) for n in (1, 2, 3)]),
    ("Reciprocal, half, NR 3-bit seed + 2 iterations (1 / 2 / 3 stages)",
     [(f"reciprocal_nr_half_seed3_2iter_{n}", 2 + 2 * 2 * n) for n in (1, 2, 3)]),
    ("Reciprocal, single, NR 7-bit seed + 2 iterations (1 / 2 / 3 stages)",
     [(f"reciprocal_nr_single_seed7_2iter_{n}", 2 + 2 * 2 * n) for n in (1, 2, 3)]),
    ("Reciprocal, single, NR 4-bit seed + 3 iterations (1 / 2 / 3 stages)",
     [(f"reciprocal_nr_single_seed4_3iter_{n}", 2 + 2 * 3 * n) for n in (1, 2, 3)]),
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
    if row.get("bram_count") not in (None, "", "0"):   # older CSVs have no BRAM column
        parts.append(f"{row['bram_count']} BRAM")
    parts.append(f"{row['lut_count']} LUT")
    return ", ".join(parts)


def reciprocal_label(design):
    """reciprocal_nr_single_seed7_2iter_3 -> Reciprocal single, NR 7-bit seed + 2 iterations, 3 stages"""
    parts = design.split("_")
    if parts[1] == "ip":
        stages = int(parts[3])
        return f"Reciprocal {parts[2]}, IP, {stages} stage{'s' if stages > 1 else ''}"
    seed, iterations, stages = parts[3][len("seed"):], parts[4][0], parts[5]
    return (f"Reciprocal {parts[2]}, NR {seed}-bit seed + {iterations} iteration{'s' if iterations != '1' else ''}, "
            f"{stages} stage{'s' if stages != '1' else ''}")


header = " | ".join(f"{f} MHz" for f in FREQUENCIES)


def print_tables(cycles_title, margins_title, cycles, label=lambda design: design):
    print(f"### {cycles_title}\n")
    print(f"| Operation | {header} |")
    print("|---|" + "---|" * len(FREQUENCIES))
    for row_label, options in cycles:
        print(f"| {row_label} | " + " | ".join(cycles_cell(options, f) for f in FREQUENCIES) + " |")

    print(f"\n### {margins_title}\n")
    print(f"| Design | Uses | {header} |")
    print("|---|---|" + "---|" * len(FREQUENCIES))
    for _, options in cycles:
        for design, _ in options:
            print(f"| {label(design)} | {uses(design)} | " + " | ".join(margin_cell(design, f) for f in FREQUENCIES) + " |")


print_tables("Clock cycles at each frequency", "Timing margins", CYCLES)
print("\n\n## For Reciprocal_Profiling_Results.md\n")
print_tables("Reciprocal: clock cycles at each frequency", "Reciprocal: timing margins",
             RECIPROCAL_CYCLES, reciprocal_label)
