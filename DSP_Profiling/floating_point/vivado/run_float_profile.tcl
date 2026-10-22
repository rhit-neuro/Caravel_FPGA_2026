# ==============================================================================
# run_float_profile.tcl
#
# Builds every floating-point design in float_designs.tcl on the KR260's FPGA
# (out of context) at each clock frequency given, and records whether it meets
# timing (setup, hold and pulse width).
#
# Each design is synthesized ONCE (synthesis doesn't depend on the clock here;
# the clock is applied afterwards), then placed and routed at each frequency.
#
# Run from a working folder (Vivado writes temporary files there), e.g.:
#   D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog \
#       -source <path>/run_float_profile.tcl -tclargs add multiply 100 200 300 400 500 600
# Numbers are frequencies; words are design-name prefixes (none = all designs).
#
# Output: results_float_<prefixes>.csv (one row per design and frequency)
# ==============================================================================

set kr260_part    xck26-sfvc784-2LV-c
set script_folder [file dirname [file normalize [info script]]]
set rtl_folder    [file normalize [file join $script_folder .. rtl]]
source [file join $script_folder float_designs.tcl]

# Split the arguments into frequencies (numbers) and design-name prefixes
set frequencies   {}
set name_prefixes {}
foreach argument $argv {
    if {[string is integer -strict $argument]} { lappend frequencies $argument } else { lappend name_prefixes $argument }
}
if {[llength $name_prefixes] > 0} {
    set selected {}
    foreach design $float_designs {
        foreach prefix $name_prefixes {
            if {[string match "${prefix}*" [lindex $design 0]]} { lappend selected $design; break }
        }
    }
    set float_designs $selected
}
set results_name [expr {[llength $name_prefixes] > 0 ? "results_float_[join $name_prefixes _].csv" : "results_float_all.csv"}]

# Worst setup (WNS), hold (WHS) and pulse-width (WPWS) slack from report_timing_summary
proc get_worst_slacks {} {
    set report [report_timing_summary -no_detailed_paths -return_string]
    regexp {WNS\(ns\)[^\n]*\n[ -]+\n\s*(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)} \
        $report -> setup_slack hold_slack pulse_width_slack
    return [list $setup_slack $hold_slack $pulse_width_slack]
}

set results [open [file join $script_folder $results_name] w]
puts $results "design,frequency_mhz,passes,setup_slack_ns,hold_slack_ns,pulse_width_slack_ns,dsp_count,lut_count"

foreach design $float_designs {
    lassign $design name harness_unit test_code ip_operation precision latency
    set data_width [expr {$precision eq "Half" ? 16 : 32}]

    # --- Sources (and the IP, freshly configured) ----------------------------
    close_project -quiet
    create_project -in_memory -part $kr260_part
    read_verilog [glob [file join $rtl_folder *.v] [file join $rtl_folder current_design *.v]]
    if {$ip_operation ne "-"} {
        set ip_folder [file normalize ip_build]
        file delete -force $ip_folder
        file mkdir $ip_folder
        create_ip -name floating_point -vendor xilinx.com -library ip -module_name float_under_test -dir $ip_folder
        configure_float_ip [get_ips float_under_test] $ip_operation $precision $latency
        set_property GENERATE_SYNTH_CHECKPOINT false [get_files float_under_test.xci]
        generate_target synthesis [get_files float_under_test.xci]
    }

    # --- Synthesize once (retried: it sometimes fails to start) --------------
    for {set attempt 1} {$attempt <= 3} {incr attempt} {
        set failed [catch {
            synth_design -top float_timing_harness -part $kr260_part -mode out_of_context \
                -generic UNIT=$harness_unit -generic DATA_WIDTH=$data_width
        } error_message]
        if {!$failed} break
        puts "Synthesis attempt $attempt failed: $error_message"
        if {$attempt == 3} { error $error_message }
    }
    set synthesized_design [file normalize synthesized.dcp]
    write_checkpoint -force $synthesized_design

    # --- Place and route at each frequency -----------------------------------
    foreach frequency_mhz $frequencies {
        close_project -quiet
        open_checkpoint $synthesized_design
        create_clock -period [format %.3f [expr {1000.0 / $frequency_mhz}]] -name clock [get_ports clock]
        opt_design
        place_design
        route_design

        lassign [get_worst_slacks] setup_slack hold_slack pulse_width_slack
        set passes [expr {$setup_slack >= 0 && $hold_slack >= 0 && $pulse_width_slack >= 0 ? "yes" : "no"}]
        set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME == DSP48E2}]]
        set lut_count [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]

        puts $results "$name,$frequency_mhz,$passes,$setup_slack,$hold_slack,$pulse_width_slack,$dsp_count,$lut_count"
        flush $results
        puts "PROFILE $frequency_mhz MHz $name passes=$passes setup=$setup_slack hold=$hold_slack pulse=$pulse_width_slack dsp=$dsp_count lut=$lut_count"
    }
}
close $results
