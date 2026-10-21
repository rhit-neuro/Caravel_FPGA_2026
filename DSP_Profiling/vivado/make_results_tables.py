"""
make_results_tables.py

Prints the Markdown timing tables for DSP_Profiling_Results.md from the
results_*MHz.csv files written by run_profile.tcl, so no number is copied by hand.

Each cell: pass/fail and the timing margin in ns = the smaller of the setup
slack and the pulse-width slack (hold slack is ~0.1 ns everywhere and doesn't
change with frequency, so it is left out).

Usage (from this folder):  python make_results_tables.py
"""
import csv
import glob
import re

FREQUENCIES = [100, 200, 300, 400, 500, 600]

# Table title -> list of (design name in the CSV, label in the table)
TABLES = {
    "16/18-bit operations": [
        ("add_1stage", "Add 18-bit, 1 stage"),
        ("add_2stages", "Add 18-bit, 2 stages"),
        ("multiply18_1stage", "Multiply 18x18, 1 stage"),
        ("multiply18_2stages", "Multiply 18x18, 2 stages"),
        ("multiply18_3stages", "Multiply 18x18, 3 stages"),
        ("multiply18_4stages", "Multiply 18x18, 4 stages"),
        ("multiply16_1stage", "Multiply 16x16, 1 stage"),
        ("multiply16_2stages", "Multiply 16x16, 2 stages"),
        ("multiply16_3stages", "Multiply 16x16, 3 stages"),
        ("multiply16_4stages", "Multiply 16x16, 4 stages"),
        ("power_shift_add", "Power 18-bit, shift-and-add"),
        ("divide16", "Divide 16-bit"),
        ("divide18", "Divide 18-bit"),
    ],
    "32-bit operations": [
        ("add32_1stage", "Add 32-bit, 1 stage"),
        ("add32_2stages", "Add 32-bit, 2 stages"),
        ("multiply32_1stage", "Multiply 32x32, 1 stage"),
        ("multiply32_2stages", "Multiply 32x32, 2 stages"),
        ("multiply32_3stages", "Multiply 32x32, 3 stages"),
        ("multiply32_4stages", "Multiply 32x32, 4 stages"),
        ("power32_shift_add", "Power 32-bit, shift-and-add"),
        ("divide32", "Divide 32-bit"),
    ],
    "Memories": [
        ("bram_read_1stage", "BRAM read, 1 stage"),
        ("bram_read_2stages", "BRAM read, 2 stages"),
        ("uram_read_1stage", "URAM read, 1 stage"),
        ("uram_read_2stages", "URAM read, 2 stages"),
        ("uram_read_3stages", "URAM read, 3 stages"),
    ],
}

# Collect every row from every results_*MHz.csv: (design, frequency) -> row
results = {}
for path in glob.glob("results_*MHz.csv"):
    frequency = int(re.search(r"_(\d+)MHz\.csv$", path).group(1))
    for row in csv.DictReader(open(path)):
        results[(row["design"], frequency)] = row


def cell(design, frequency):
    row = results.get((design, frequency))
    if row is None:
        return "–"
    margin = min(float(row["setup_slack_ns"]), float(row["pulse_width_slack_ns"]))
    return ("✅" if row["passes"] == "yes" else "❌") + f" {margin:+.2f}"


def resources(design):
    row = results.get((design, 100))
    if row is None:
        return "–"
    parts = [f"{row[key]} {name}" for key, name in
             [("dsp_count", "DSP"), ("bram_count", "BRAM"), ("uram_count", "URAM"), ("lut_count", "LUT")]
             if row.get(key) not in (None, "", "0")]
    return ", ".join(parts) or "–"


# Clock cycles per operation (from simulation; they don't depend on frequency).
# One row per operation: (label, [(design whose timing decides pass/fail, cycles), ...]).
# Operations with several pipeline-stage options list one entry per option;
# the table cell then shows the cycle counts of the options that pass.
CYCLES = [
    ("Add 18-bit (1–2 stages)", [("add_1stage", 1), ("add_2stages", 2)]),
    ("Add 32-bit (1–2 stages)", [("add32_1stage", 1), ("add32_2stages", 2)]),
    ("Multiply 16x16 (1–4 stages)", [("multiply16_1stage", 1), ("multiply16_2stages", 2),
                                     ("multiply16_3stages", 3), ("multiply16_4stages", 4)]),
    ("Multiply 18x18 (1–4 stages)", [("multiply18_1stage", 1), ("multiply18_2stages", 2),
                                     ("multiply18_3stages", 3), ("multiply18_4stages", 4)]),
    ("Multiply 32x32 (1–4 stages)", [("multiply32_1stage", 1), ("multiply32_2stages", 2),
                                     ("multiply32_3stages", 3), ("multiply32_4stages", 4)]),
    ("Divide 16-bit", [("divide16", 30)]),
    ("Divide 18-bit", [("divide18", 36)]),
    ("Divide 32-bit", [("divide32", 50)]),
    ("Power x^5 18-bit", [("power_shift_add", 74)]),
    ("Power x^5 32-bit", [("power32_shift_add", 130)]),
    ("BRAM write", [("bram_read_1stage", 1)]),
    ("BRAM read (1–2 stages)", [("bram_read_1stage", 1), ("bram_read_2stages", 2)]),
    ("URAM write", [("uram_read_2stages", 1)]),   # write works wherever the URAM block does
    ("URAM read (1–3 stages)", [("uram_read_1stage", 1), ("uram_read_2stages", 2),
                                ("uram_read_3stages", 3)]),
]

# DDR4 average cycles, measured on the board (ddr_results_<f>MHz.csv)
DDR_LABELS = {"single_write": "DDR4 single write (16 B)", "single_read": "DDR4 single read (16 B)",
              "burst_write": "DDR4 burst write (256 B)", "burst_read": "DDR4 burst read (256 B)"}
ddr_cycles = {}
for path in glob.glob("ddr_results_*MHz.csv"):
    for row in csv.DictReader(open(path)):
        ddr_cycles[(row["test"], int(row["frequency_mhz"]))] = round(float(row["average_cycles"]))


def cycles_cell(options, frequency):
    """Cycle counts of the stage options that pass at this frequency, e.g. "1–4" or "2–3"."""
    if any(results.get((design, frequency)) is None for design, _ in options):
        return "–"
    passing = [cycles for design, cycles in options if results[(design, frequency)]["passes"] == "yes"]
    if not passing:
        return "❌"
    return str(passing[0]) if len(passing) == 1 else f"{passing[0]}–{passing[-1]}"


print("\n### Clock cycles at each frequency\n")
print("| Operation | " + " | ".join(f"{f} MHz" for f in FREQUENCIES) + " |")
print("|---|" + "---|" * len(FREQUENCIES))
for label, options in CYCLES:
    print(f"| {label} | " + " | ".join(cycles_cell(options, f) for f in FREQUENCIES) + " |")
for test, label in DDR_LABELS.items():
    cells = [str(ddr_cycles[(test, f)]) if (test, f) in ddr_cycles else "–" for f in FREQUENCIES]
    print(f"| {label} | " + " | ".join(cells) + " |")

for title, designs in TABLES.items():
    print(f"\n### {title}\n")
    print("| Design | Uses | " + " | ".join(f"{f} MHz" for f in FREQUENCIES) + " |")
    print("|---|---|" + "---|" * len(FREQUENCIES))
    for design, label in designs:
        print(f"| {label} | {resources(design)} | " + " | ".join(cell(design, f) for f in FREQUENCIES) + " |")
