# ==============================================================================
# run_ddr_test.tcl
#
# Runs the DDR test through the VIO debug core over JTAG, and prints/saves the
# measured cycle counts.
#
# Before running: the board is at the U-Boot prompt (so the DDR is set up) and
# the FPGA was programmed through U-Boot with load_bitstream_uboot.py (which
# also powers up the FPGA fabric). This script does not reprogram the FPGA.
#
# Run from this folder, e.g. for the 200 MHz build:
#   D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog \
#       -source run_ddr_test.tcl -tclargs 200
#
# Output: ddr_results_<MHz>MHz.csv
# ==============================================================================

set test_clock_mhz     [lindex $argv 0]
set transfers_per_test 64
set script_folder      [file dirname [file normalize [info script]]]
set probes_file        [file join $script_folder ddr_tester_${test_clock_mhz}MHz.ltx]

# --- Attach to the already-programmed FPGA ---------------------------------------
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set fpga [lindex [get_hw_devices xck26*] 0]
current_hw_device $fpga
set_property PROBES.FILE $probes_file $fpga
refresh_hw_device $fpga

set vio [lindex [get_hw_vios -of_objects $fpga] 0]
if {$vio eq ""} { error "VIO core not found: is the PL clock running?" }

# Find each VIO probe by the net it is connected to
proc probe {pattern} {
    global vio
    set found [get_hw_probes -of_objects $vio -filter "NAME =~ *${pattern}*"]
    if {[llength $found] != 1} { error "expected one probe matching '$pattern', found: $found" }
    return $found
}
set reset_probe   [probe probe_out0]
set start_probe   [probe probe_out1]
set done_probe    [probe done]
set timeout_probe [probe timed_out]
set errors_probe  [probe error_count]
set minimum_probe [probe minimum_cycles]
set maximum_probe [probe maximum_cycles]
set total_probe   [probe total_cycles]

proc write_probe {probe_object value} {
    global vio
    set_property OUTPUT_VALUE $value $probe_object
    commit_hw_vio $vio
}
proc read_probe {probe_object} {
    return [expr "0x[get_property INPUT_VALUE $probe_object]"]   ;# hex string -> number
}

# --- Run: reset, then a rising edge on start -----------------------------------
write_probe $start_probe 0
write_probe $reset_probe 1
write_probe $reset_probe 0
write_probe $start_probe 1

# Wait up to 10 s for done (or a timeout inside the tester)
for {set poll 0} {$poll < 100} {incr poll} {
    refresh_hw_vio $vio
    if {[read_probe $done_probe] || [read_probe $timeout_probe]} break
    after 100
}

set done      [read_probe $done_probe]
set timed_out [read_probe $timeout_probe]
set errors    [read_probe $errors_probe]
set minimums  [read_probe $minimum_probe]
set maximums  [read_probe $maximum_probe]
set totals    [read_probe $total_probe]
puts "DDR_TEST ${test_clock_mhz}MHz done=$done timed_out=$timed_out errors=$errors"

# --- Unpack the 4 tests and save --------------------------------------------------
set test_names {single_write single_read burst_write burst_read}
set clock_period_ns [expr {1000.0 / $test_clock_mhz}]
set results [open [file join $script_folder ddr_results_${test_clock_mhz}MHz.csv] w]
puts $results "test,frequency_mhz,min_cycles,max_cycles,average_cycles,average_ns,errors,timed_out"

for {set test 0} {$test < 4} {incr test} {
    set minimum [expr {($minimums >> (16 * $test)) & 0xFFFF}]
    set maximum [expr {($maximums >> (16 * $test)) & 0xFFFF}]
    set total   [expr {($totals   >> (32 * $test)) & 0xFFFFFFFF}]
    set average [expr {double($total) / $transfers_per_test}]
    set line [format "%s,%d,%d,%d,%.1f,%.1f,%d,%d" [lindex $test_names $test] $test_clock_mhz \
        $minimum $maximum $average [expr {$average * $clock_period_ns}] $errors $timed_out]
    puts $results $line
    puts "DDR_RESULT $line"
}
close $results
close_hw_target
disconnect_hw_server
