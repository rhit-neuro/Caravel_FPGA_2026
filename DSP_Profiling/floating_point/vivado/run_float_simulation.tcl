# ==============================================================================
# run_float_simulation.tcl
#
# Simulates every floating-point design in float_designs.tcl with Vivado's
# simulator (xsim; the IP's simulation model needs it), one run per design,
# and collects the PASS/FAIL lines into float_sim_results.txt.
#
# Run from this folder:
#   D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog -source run_float_simulation.tcl
# Add design-name prefixes to simulate only those, e.g. "-tclargs current_mac".
# ==============================================================================

set script_folder [file dirname [file normalize [info script]]]
set rtl_folder    [file normalize [file join $script_folder .. rtl]]
set tb_file       [file normalize [file join $script_folder .. tb tb_float_profile.sv]]
# The simulator fails to start in a folder whose path has a space
# ("NeuroProcessor Project"), so the simulation project goes in TEMP.
set build_folder  [file normalize [file join $::env(TEMP) float_sim_build]]
source [file join $script_folder float_designs.tcl]

# Optional: only the designs whose names start with the given prefixes
if {[llength $argv] > 0} {
    set selected {}
    foreach design $float_designs {
        foreach prefix $argv {
            if {[string match "${prefix}*" [lindex $design 0]]} { lappend selected $design; break }
        }
    }
    set float_designs $selected
}
set results_file [expr {[llength $argv] > 0 ? "float_sim_results_[join $argv _].txt" : "float_sim_results.txt"}]

file delete -force $build_folder
create_project float_sim $build_folder -part xck26-sfvc784-2LV-c
add_files [list \
    [file join $rtl_folder float_ip_unit.v] \
    [file join $rtl_folder float_power.v] \
    [file join $rtl_folder current_design_float_unit.v] \
    [file join $rtl_folder float_newton_raphson_reciprocal.v] \
    [file normalize [file join $rtl_folder .. .. rtl newton_raphson_core.v]] \
    [file normalize [file join $rtl_folder .. .. rtl nr_multiply_add.v]]]
add_files [glob [file join $rtl_folder current_design *.v]]
add_files -fileset sim_1 [list $tb_file]
set_property top tb_float_profile [get_filesets sim_1]
set_property -name xsim.simulate.runtime -value -all -objects [get_filesets sim_1]

# The IP, created once and reconfigured for each design
create_ip -name floating_point -vendor xilinx.com -library ip -module_name float_under_test
set ip [get_ips float_under_test]

set summary [open [file join $script_folder $results_file] w]
foreach design $float_designs {
    lassign $design name harness_unit test_code ip_operation precision latency seed_bits iterations
    set data_width [expr {$precision eq "Half" ? 16 : 32}]
    if {$seed_bits eq ""} { set seed_bits 7; set iterations 1 }   ;# unused by the other designs

    if {$ip_operation ne "-"} {
        configure_float_ip $ip $ip_operation $precision $latency
        generate_target simulation [get_files float_under_test.xci]
    }
    set_property verilog_define [list OPERATION_CODE=$test_code DATA_WIDTH_VALUE=$data_width LATENCY_VALUE=$latency \
                                      SEED_BITS_VALUE=$seed_bits ITERATIONS_VALUE=$iterations] \
        [get_filesets sim_1]

    launch_simulation -simset sim_1 -mode behavioral
    close_sim

    # Keep the testbench's own result lines
    set log_file [file join $build_folder float_sim.sim sim_1 behav xsim simulate.log]
    puts $summary "== $name"
    foreach line [split [read [set handle [open $log_file]]] "\n"] {
        if {[regexp {^(PASS|FAIL|Tests:)} $line]} { puts $summary $line; puts "SIM $name: $line" }
    }
    close $handle
    flush $summary
}
close $summary
