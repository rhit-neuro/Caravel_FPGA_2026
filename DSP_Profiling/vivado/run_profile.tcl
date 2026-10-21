# ==============================================================================
# run_profile.tcl
#
# Builds each profiled design on the KR260's FPGA (synthesis, placement and
# routing, out of context) with the 12 MHz synaptic module clock as the timing
# target. For each design it records:
#   - how many DSPs, LUTs and flip-flops it uses
#   - the timing slack at 12 MHz (how much of the clock period is left over)
#   - which DSP48E2 internal registers Vivado used
#
# Run from this folder:
#   D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_profile.tcl
#
# Output: results.csv, plus timing_<design>.rpt (the slowest path of each design)
# ==============================================================================

set kr260_part      xck26-sfvc784-2LV-c   ;# Kria K26 SoM used on the KR260
set clock_period_ns 83.333                ;# 12 MHz synaptic module clock
set script_folder   [file dirname [file normalize [info script]]]
set rtl_folder      [file join $script_folder .. rtl]
set results_file    [file join $script_folder results.csv]

# Designs to build. Each row is:
#   design_name  operation  data_width  fraction_bits
# operation: 0 = dsp_adder, 1 = dsp_fixed_point_multiplier, 2 = shift_add_power
set designs {
    {add_18bit        0  18  16}
    {add_32bit        0  32  16}
    {multiply_18x18   1  18  16}
    {multiply_16x16   1  16  12}
    {power_shift_add  2  18  16}
}

set results [open $results_file w]
puts $results "design,dsp_count,lut_count,flip_flop_count,slack_at_12mhz_ns,dsp_registers_used"

foreach design $designs {
    lassign $design design_name operation data_width fraction_bits

    # --- Build ---------------------------------------------------------------
    close_project -quiet
    create_project -in_memory -part $kr260_part
    read_verilog [glob [file join $rtl_folder *.v]]
    synth_design -top timing_harness -part $kr260_part -mode out_of_context \
        -generic OPERATION=$operation \
        -generic DATA_WIDTH=$data_width \
        -generic FRACTION_BITS=$fraction_bits
    create_clock -period $clock_period_ns -name clock [get_ports clock]
    opt_design
    place_design
    route_design

    # --- Resource counts -----------------------------------------------------
    set dsp_cells       [get_cells -hierarchical -filter {REF_NAME == DSP48E2}]
    set dsp_count       [llength $dsp_cells]
    set lut_count       [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
    set flip_flop_count [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]

    # --- Which DSP internal registers were used ------------------------------
    # A/B/C = input registers, M = multiplier register, P = output register.
    # 1 means that register is in use, 0 means it is bypassed.
    set dsp_register_summary {}
    foreach dsp $dsp_cells {
        lappend dsp_register_summary [format "A%s B%s C%s M%s P%s" \
            [get_property AREG $dsp] [get_property BREG $dsp] [get_property CREG $dsp] \
            [get_property MREG $dsp] [get_property PREG $dsp]]
    }

    # --- Timing --------------------------------------------------------------
    # Positive slack = the slowest path finishes this many ns before the next
    # 12 MHz clock edge, so the design meets timing.
    set slack_ns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]

    puts $results "$design_name,$dsp_count,$lut_count,$flip_flop_count,$slack_ns,[join $dsp_register_summary {;}]"
    flush $results
    report_timing -max_paths 1 -file [file join $script_folder "timing_$design_name.rpt"]
    puts "PROFILE $design_name dsp=$dsp_count lut=$lut_count ff=$flip_flop_count slack=$slack_ns dsp_registers=$dsp_register_summary"
}

close $results
