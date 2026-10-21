# ==============================================================================
# run_profile.tcl
#
# Builds every design on the KR260's FPGA (synthesis, placement, routing; out
# of context) at each clock frequency given on the command line, and records
# whether it meets timing.
#
# A design PASSES at a frequency only if all three timing checks pass:
#   setup slack >= 0   (signals arrive before the next clock edge)
#   hold slack  >= 0   (signals don't change too soon after a clock edge)
#   pulse width >= 0   (the clock isn't faster than the DSP/BRAM itself allows)
#
# Run from this folder, e.g. for 100 and 200 MHz:
#   D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog \
#       -source run_profile.tcl -tclargs 100 200
#
# Output: results_<frequency>MHz.csv for each frequency
# ==============================================================================

set kr260_part    xck26-sfvc784-2LV-c   ;# Kria K26 SoM used on the KR260
set frequencies   $argv                 ;# MHz values from -tclargs
set script_folder [file dirname [file normalize [info script]]]
set rtl_folder    [file join $script_folder .. rtl]

# Designs to build. Each row is:
#   design_name  operation  data_width  fraction_bits  pipeline_stages
# operation: 0 = adder, 1 = fixed-point multiplier, 2 = shift-add power, 3 = BRAM
set designs {
    {add_1stage           0  18  16  1}
    {add_2stages          0  18  16  2}
    {multiply18_1stage    1  18  16  1}
    {multiply18_2stages   1  18  16  2}
    {multiply18_3stages   1  18  16  3}
    {multiply18_4stages   1  18  16  4}
    {multiply16_1stage    1  16  12  1}
    {multiply16_2stages   1  16  12  2}
    {multiply16_3stages   1  16  12  3}
    {multiply16_4stages   1  16  12  4}
    {power_shift_add      2  18  16  1}
    {bram_read_1stage     3  18  16  1}
    {bram_read_2stages    3  18  16  2}
}

# Pull worst setup (WNS), hold (WHS) and pulse-width (WPWS) slack out of the
# "Design Timing Summary" table of report_timing_summary.
proc get_worst_slacks {} {
    set report [report_timing_summary -no_detailed_paths -return_string]
    regexp {WNS\(ns\)[^\n]*\n[ -]+\n\s*(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)} \
        $report -> setup_slack hold_slack pulse_width_slack
    return [list $setup_slack $hold_slack $pulse_width_slack]
}

foreach frequency_mhz $frequencies {
    set clock_period_ns [format %.3f [expr {1000.0 / $frequency_mhz}]]
    set results [open [file join $script_folder "results_${frequency_mhz}MHz.csv"] w]
    puts $results "design,frequency_mhz,passes,setup_slack_ns,hold_slack_ns,pulse_width_slack_ns,dsp_count,bram_count,lut_count"

    foreach design $designs {
        lassign $design design_name operation data_width fraction_bits pipeline_stages

        # --- Build -----------------------------------------------------------
        close_project -quiet
        create_project -in_memory -part $kr260_part
        read_verilog [glob [file join $rtl_folder *.v]]
        # Synthesis sometimes fails to start when several Vivado processes
        # launch at the same moment, so try up to 3 times.
        for {set attempt 1} {$attempt <= 3} {incr attempt} {
            set failed [catch {
                synth_design -top timing_harness -part $kr260_part -mode out_of_context \
                    -generic OPERATION=$operation \
                    -generic DATA_WIDTH=$data_width \
                    -generic FRACTION_BITS=$fraction_bits \
                    -generic PIPELINE_STAGES=$pipeline_stages
            } error_message]
            if {!$failed} break
            puts "Synthesis attempt $attempt failed: $error_message"
            if {$attempt == 3} { error $error_message }
        }
        create_clock -period $clock_period_ns -name clock [get_ports clock]
        opt_design
        place_design
        route_design

        # --- Timing ----------------------------------------------------------
        lassign [get_worst_slacks] setup_slack hold_slack pulse_width_slack
        set passes [expr {$setup_slack >= 0 && $hold_slack >= 0 && $pulse_width_slack >= 0 ? "yes" : "no"}]

        # --- Resources -------------------------------------------------------
        set dsp_count  [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E2}]]
        set bram_count [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]]
        set lut_count  [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]

        puts $results "$design_name,$frequency_mhz,$passes,$setup_slack,$hold_slack,$pulse_width_slack,$dsp_count,$bram_count,$lut_count"
        flush $results
        puts "PROFILE $frequency_mhz MHz $design_name passes=$passes setup=$setup_slack hold=$hold_slack pulse=$pulse_width_slack"
    }
    close $results
}
