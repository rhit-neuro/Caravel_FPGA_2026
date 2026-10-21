# =============================================================================
# run_timing_sweep.tcl  --  build fp_timing_top for the KR260 at each clock
#                           frequency, then measure latency + correctness
#                           with real delays                            (v2)
# =============================================================================
# *** AI DISCLOSURE: written with support from Claude (Anthropic) in Claude Code, Oct 20-21, 2026 -- code, comments and debugging. ***
# Run from the FP32_Sims folder, in the Vivado Tcl Shell (or any shell where
# Vivado is set up):
#     vivado -mode batch -source scripts/run_timing_sweep.tcl
# Roughly 5-10 minutes per frequency.
#
# WHAT IT DOES
#   0. RTL simulation once (no delays): checks the logic before building.
#   For each frequency:
#   1. Synthesize, place and route fp_timing_top on the K26 chip.
#   2. Static timing analysis (STA): setup, hold and pulse-width slack for
#      every unit. STA checks EVERY path; it is the acceptance test.
#   3. Timing simulation: run the same testbench on the routed netlist with
#      real gate + wire delays (SDF file), twice:
#        slow corner + max delays  -> catches setup problems
#        fast corner + min delays  -> catches hold problems
#      (AMD's recommended method, UG900 "Running Timing Simulation".)
#      The testbench measures latency and checks every answer.
#   4. Verdict per unit: PASS only if setup, hold and pulse width all have
#      slack >= 0 AND both timing simulations got every answer right with a
#      constant latency.
#
# OUTPUT (in FP32_Sims/reports/)
#   summary.md                    one table per frequency (read this first)
#   timing_sweep.csv              everything, one row per (frequency, unit)
#   rtl_sim.log                   the RTL simulation
#   <MHz>MHz_timing.rpt           Vivado timing report
#   <MHz>MHz_util.rpt             resources per unit
#   sim_<MHz>MHz/{slow,fast}/     timing-simulation logs
#
# CHANGES FROM v1 (from the 10/21 report)
#   * latency is measured by the testbench, not typed into this script
#   * hold and pulse width are reported per unit, not just setup
#   * pins are behind boundary registers (see fp_timing_top.v) and the
#     pin-to-register paths are excluded, so the made-up pin locations no
#     longer cause fake hold failures
#   * LUT/FF counts use REF_NAME (the v1 PRIMITIVE_GROUP query returned 0)
# =============================================================================

set part   xck26-sfvc784-2LV-c           ;# the chip on the KR260 (K26 SOM)
set top    fp_timing_top
set freqs  {12 100 200 300 400 500 600}  ;# MHz, from the team's list
# quick test of a few frequencies:  set FP_FREQS=12 (Windows) before running
if {[info exists ::env(FP_FREQS)]} { set freqs $::env(FP_FREQS) }

set run_timing_sim  1      ;# 0 = skip the timing simulations (much faster)
set n_random_timing 3000   ;# random problems per timing simulation

# unit instance name -> label (labels match the testbench's RESULT lines)
set units {
    u_add   add
    u_mul   multiply
    u_shift shift
    u_exp   exp
    u_bram  bram_read
    u_uram  uram_read
    u_ddr4  ddr4_read
}

# ---- folders: this script lives in FP32_Sims/scripts
set root [file normalize [file join [file dirname [info script]] ..]]
set rep  $root/reports
file mkdir $rep
set rtl_files [glob $root/rtl/*.v]
set tb_files  [list $root/sim/tb_fp_timing_top.v $root/sim/axi_mem_model.v]
set glbl      [file join $::env(XILINX_VIVADO) data verilog src glbl.v]
# Patched copy of AMD's CARRY8 model used in timing simulation only: AMD's
# model let a stale sum stick on the adder's carry chain in xsim 2023.2
# (a simulator problem, not a chip problem). Details in the file's header.
set fix_files [list $root/sim/xsim_fix/CARRY8.v]

# =============================================================================
# Helper procedures (Tcl "proc" = function)
# =============================================================================

# Full path of a Vivado simulator tool. On Windows the tools are .bat files.
proc tool {name} {
    set ext [expr {$::tcl_platform(platform) eq "windows" ? ".bat" : ""}]
    return [file nativename [file join $::env(XILINX_VIVADO) bin $name$ext]]
}

# Run a command inside folder 'dir', save its output to 'logfile', return the output.
proc run_in {dir logfile args} {
    set here [pwd]
    cd $dir
    set rc [catch {exec -ignorestderr {*}$args 2>@1} out]
    cd $here
    set f [open $logfile a]; puts $f $out; close $f
    if {$rc} { puts ">>> WARNING: command returned an error, see $logfile" }
    return $out
}

# Write 'words' to a command file, one per line (for "tool -f file").
proc write_cmd_file {path words} {
    set f [open $path w]
    foreach w $words { puts $f $w }
    close $f
}

# Compile, elaborate and run the testbench in folder 'dir'. 'extra_elab' holds
# the timing-simulation options (empty for RTL simulation). 'fix_files' are
# compiled into library xsim_fix first and searched before AMD's libraries
# (timing simulation only, see sim/xsim_fix/CARRY8.v). Returns the log.
proc run_sim {dir sources defines extra_elab tops {fix_files {}}} {
    file mkdir $dir
    set log $dir/sim.log
    file delete -force $log
    # All options go in command files (tool -f file), one per line, instead
    # of on the command line. On Windows xvlog/xelab are .bat files, and cmd
    # splits "-d CLK_PS=83333" at the '=' into "-d CLK_PS 83333" -- xvlog then
    # thought 83333 was a source file (v2 error XSIM 43-4316). A file is read
    # by the tool itself, so cmd never touches it. (Like passing argv through
    # a file instead of a shell that mangles it.)
    set libs {}
    if {[llength $fix_files]} {
        set words {--work xsim_fix}
        foreach s $fix_files { lappend words [file normalize $s] }
        write_cmd_file $dir/xvlog_fix.f $words
        run_in $dir $log [tool xvlog] -f xvlog_fix.f
        set libs {-L xsim_fix}
    }
    set words {}
    foreach d $defines { lappend words "-d $d" }
    foreach s $sources { lappend words [file normalize $s] }
    write_cmd_file $dir/xvlog.f $words
    run_in $dir $log [tool xvlog] -f xvlog.f

    write_cmd_file $dir/xelab.f [list "--relax $libs $extra_elab -s snap $tops"]
    run_in $dir $log [tool xelab] -f xelab.f
    return [run_in $dir $log [tool xsim] snap -R]
}

# Pull the testbench's "RESULT unit=..." lines out of a log.
# Fills array 'res' with res(<unit>) = {sent correct wrong x missing extra lat_min lat_max}
proc parse_results {log arrname} {
    upvar $arrname res
    foreach {all u s c w x m e lmin lmax} [regexp -all -inline \
        {RESULT unit=(\S+) sent=(\d+) correct=(\d+) wrong=(\d+) x=(\d+) missing=(-?\d+) extra=(\d+) lat_min=(-?\d+) lat_max=(-?\d+)} $log] {
        set res($u) [list $s $c $w $x $m $e $lmin $lmax]
    }
}

# 1 if a RESULT entry is a clean pass
proc sim_ok {entry} {
    lassign $entry s c w x m e lmin lmax
    return [expr {$s > 0 && $c == $s && $w == 0 && $x == 0 && $m == 0 && $e == 0 && $lmin == $lmax}]
}

# Cells that belong to one unit and hold state (flip-flops, DSPs, RAMs)
proc unit_cells {inst} {
    return [get_cells -quiet -hier -filter \
        "NAME =~ $inst/* && (IS_SEQUENTIAL || REF_NAME =~ DSP* || REF_NAME =~ RAMB* || REF_NAME =~ URAM*)"]
}

# Worst slack of paths starting OR ending in a unit. kind = -setup or -hold
proc unit_slack {inst kind} {
    set cells [unit_cells $inst]
    if {[llength $cells] == 0} { return "n/a" }
    set worst ""
    foreach dir {-to -from} {
        set p [get_timing_paths -quiet $kind -max_paths 1 $dir $cells]
        if {[llength $p]} {
            set s [get_property SLACK $p]
            if {$s ne "" && ($worst eq "" || $s < $worst)} { set worst $s }
        }
    }
    return [expr {$worst eq "" ? "n/a" : $worst}]
}

# Worst pulse-width slack inside a unit (DSP/BRAM/URAM have minimum clock
# periods of their own). Returns "" if Vivado won't report per cell.
proc unit_pulse_slack {inst} {
    set cells [unit_cells $inst]
    if {[llength $cells] == 0} { return "" }
    if {[catch {report_pulse_width -cells $cells -return_string} txt]} { return "" }
    set worst ""
    foreach {all slack} [regexp -all -inline -line \
        {(?:Min Period|Low Pulse Width|High Pulse Width|Max Skew)\s+\S+\s+\S+\s+\S+\s+[-0-9.]+\s+[-0-9.]+\s+([-0-9.]+)} $txt] {
        if {$worst eq "" || $slack < $worst} { set worst $slack }
    }
    return $worst
}

proc count_cells {inst filter} {
    return [llength [get_cells -quiet -hier -filter "NAME =~ $inst/* && $filter"]]
}

# =============================================================================
# 0. RTL simulation (no delays) -- make sure the logic is right first
# =============================================================================
puts "\n>>> ===== RTL simulation ====="
set rtl_log [run_sim $rep/rtl_sim [concat $rtl_files $tb_files] {} {} {work.tb_fp_timing_top}]
file copy -force $rep/rtl_sim/sim.log $rep/rtl_sim.log
array unset rtl_res
parse_results $rtl_log rtl_res
set rtl_pass [regexp {OVERALL PASS} $rtl_log]
puts ">>> RTL simulation: [expr {$rtl_pass ? "PASS" : "FAIL -- see reports/rtl_sim.log"}]"
if {!$rtl_pass} { puts ">>> Stopping: fix the RTL before timing it."; return }

# =============================================================================
# Sweep
# =============================================================================
set csv [open $rep/timing_sweep.csv w]
puts $csv "freq_MHz,period_ns,unit,latency_cycles,latency_ns,setup_slack_ns,hold_slack_ns,pulse_slack_ns,est_fmax_MHz,sim_slow,sim_fast,LUT,FF,SRL,DSP,BRAM,URAM,verdict"
set md [open $rep/summary.md w]
puts $md "# FP32 operation timing sweep on the KR260 (xck26-sfvc784-2LV-c)\n"
puts $md "Latency is measured by the testbench in timing simulation. Slack is from Vivado static timing (negative = violation). A unit PASSES at a frequency only if setup, hold and pulse width all meet timing AND both timing simulations (slow/max and fast/min delays) returned every answer correctly with constant latency.\n"

foreach mhz $freqs {
    set period [format %.3f [expr {1000.0 / $mhz}]]
    set clk_ps [expr {round(1000000.0 / $mhz)}]
    puts "\n>>> ===== $mhz MHz (period $period ns) ====="

    # --- 1. build
    create_project -in_memory -part $part
    read_verilog $rtl_files
    set xdc $rep/clk_${mhz}MHz.xdc
    set f [open $xdc w]
    puts $f "create_clock -period $period -name clk \[get_ports clk\]"
    puts $f "# Pins sit behind boundary registers (fp_timing_top.v), which stand in for"
    puts $f "# the neighbouring on-chip logic. Pin <-> register paths are not part of"
    puts $f "# the measurement (out-of-context pins have no real location)."
    puts $f "set_false_path -from \[get_ports -filter {DIRECTION == IN && NAME != clk}\]"
    puts $f "set_false_path -to   \[get_ports -filter {DIRECTION == OUT}\]"
    close $f
    read_xdc $xdc
    synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy none
    opt_design
    place_design
    phys_opt_design
    route_design

    # --- 2. static timing
    set summ [report_timing_summary -no_detailed_paths -return_string]
    set d_wns "?"; set d_whs "?"; set d_wpws "?"
    regexp {WPWS\(ns\)[^\n]*\n[^\n]*\n\s*(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)} \
        $summ -> d_wns d_whs d_wpws
    report_timing_summary -file $rep/${mhz}MHz_timing.rpt
    report_utilization -hierarchical -file $rep/${mhz}MHz_util.rpt

    # --- 3. timing simulations
    array unset simres
    if {$run_timing_sim} {
        foreach corner {slow fast} dflag {-maxdelay -mindelay} {
            set d $rep/sim_${mhz}MHz/$corner
            file mkdir $d
            write_verilog -force -mode timesim -sdf_anno true -sdf_file $d/top.sdf $d/top_timesim.v
            write_sdf     -force -process_corner $corner $d/top.sdf
            puts ">>> timing simulation, $corner corner ..."
            set log [run_sim $d [concat [list $d/top_timesim.v] $tb_files [list $glbl]] \
                         [list CLK_PS=$clk_ps N_RANDOM=$n_random_timing] \
                         [list -L simprims_ver -L secureip $dflag -transport_int_delays \
                               -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0] \
                         {work.tb_fp_timing_top work.glbl} $fix_files]
            array unset r
            parse_results $log r
            foreach {inst label} $units {
                set simres($corner,$label) [expr {[info exists r($label)] ? $r($label) : ""}]
            }
            if {[regexp {outputs change (\S+) ns after clk} $log -> c2o]} {
                puts ">>> ($corner) clock-to-output measured by testbench: $c2o ns"
            }
        }
    }

    # --- 4. per-unit results
    puts $md "## $mhz MHz ($period ns)\n"
    puts $md "Design-wide: setup WNS $d_wns ns, hold WHS $d_whs ns, pulse-width WPWS $d_wpws ns\n"
    puts $md "| Unit | Measured latency | Correct (slow / fast sim) | Setup / hold / pulse slack (ns) | Est. Fmax | Assessment |"
    puts $md "| --- | --- | --- | --- | --- | --- |"

    foreach {inst label} $units {
        set setup [unit_slack $inst -setup]
        set hold  [unit_slack $inst -hold]
        set pw    [unit_pulse_slack $inst]
        if {$pw eq ""} { set pw $d_wpws }        ;# fall back to the design-wide value
        set fmax  [expr {[string is double -strict $setup] ? [format %.1f [expr {1000.0 / ($period - $setup)}]] : "?"}]

        # latency + correctness from the timing sims (or RTL sim if skipped)
        set slow_txt "skipped"; set fast_txt "skipped"; set sims_ok 1; set lat "?"
        if {$run_timing_sim} {
            foreach corner {slow fast} {
                set e $simres($corner,$label)
                if {$e eq ""} { set txt "no result"; set sims_ok 0 } else {
                    lassign $e s c w x m ex lmin lmax
                    set txt "$c/$s"
                    if {$x > 0}  { append txt " X=$x" }
                    if {$m != 0} { append txt " missing=$m" }
                    if {$lmin != $lmax} { append txt " latency $lmin-$lmax" }
                    if {![sim_ok $e]} { set sims_ok 0 }
                    if {$corner eq "slow"} { set lat $lmax }
                }
                if {$corner eq "slow"} { set slow_txt $txt } else { set fast_txt $txt }
            }
        } elseif {[info exists rtl_res($label)]} {
            set lat [lindex $rtl_res($label) 7]
        }
        set lat_ns [expr {[string is integer -strict $lat] ? [format %.2f [expr {$lat * $period}]] : "?"}]
        if {$label eq "ddr4_read"} { set lat_ns "fake model" }

        set sta_ok [expr {[string is double -strict $setup] && $setup >= 0 &&
                          [string is double -strict $hold]  && $hold  >= 0 &&
                          (![string is double -strict $pw] || $pw >= 0)}]
        set verdict [expr {$sta_ok && $sims_ok ? "PASS" : "FAIL"}]

        set lut  [count_cells $inst {REF_NAME =~ LUT*}]
        set ff   [count_cells $inst {REF_NAME =~ FD*}]
        set srl  [count_cells $inst {REF_NAME =~ SRL*}]
        # physical DSP blocks only: after routing each DSP48E2 also shows up
        # as ~8 internal sub-cells (DSP_ALU, DSP_M_DATA, ...) which REF_NAME =~ DSP*
        # also matched, so v2 reported 18 for multiply instead of 2
        set dsp  [count_cells $inst {REF_NAME == DSP48E2}]
        set bram [count_cells $inst {REF_NAME =~ RAMB*}]
        set uram [count_cells $inst {REF_NAME =~ URAM*}]

        puts $csv "$mhz,$period,$label,$lat,$lat_ns,$setup,$hold,$pw,$fmax,$slow_txt,$fast_txt,$lut,$ff,$srl,$dsp,$bram,$uram,$verdict"
        puts $md "| $label | $lat cycles / $lat_ns ns | $slow_txt / $fast_txt | $setup / $hold / $pw | $fmax MHz | $verdict |"
        puts [format ">>> %4s MHz  %-10s lat %3s cyc  setup %7s  hold %7s  pw %7s  sim %s | %s  -> %s" \
                  $mhz $label $lat $setup $hold $pw $slow_txt $fast_txt $verdict]
    }
    puts $md ""
    flush $csv; flush $md
    close_project
}

puts $md "Resource counts per unit (LUT, FF, SRL, DSP, BRAM, URAM) are in timing_sweep.csv."
puts $md "DDR4 latency comes from a fake memory model; real DDR4 latency needs the board."
close $csv
close $md
puts "\n>>> done -- read reports/summary.md (full data in reports/timing_sweep.csv)"
