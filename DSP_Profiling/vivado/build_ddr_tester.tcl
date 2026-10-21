# ==============================================================================
# build_ddr_tester.tcl
#
# Builds a KR260 bitstream that measures DDR4 read/write cycles from the FPGA.
#
#   Zynq PS  (only the HP0 port is used: 128-bit AXI into the DDR controller)
#     ^
#     | AXI4
#   ddr_latency_tester  <-- clock from clk_wiz (TEST_CLOCK_MHZ)
#     ^
#     | start/reset in, results out
#   VIO debug core  <-- read and written over JTAG by run_ddr_test.tcl
#
# Run from this folder, e.g. for 200 MHz:
#   D:/Vivado/2023.2/bin/vivado.bat -mode batch -nojournal -nolog \
#       -source build_ddr_tester.tcl -tclargs 200
#
# Output: ddr_tester_<MHz>MHz.bit and ddr_tester_<MHz>MHz.ltx (VIO probe names)
# ==============================================================================

set test_clock_mhz [lindex $argv 0]
set script_folder  [file dirname [file normalize [info script]]]
set rtl_folder     [file join $script_folder .. rtl]
set build_folder   [file join $script_folder ddr_build_${test_clock_mhz}MHz]

file delete -force $build_folder
create_project ddr_tester $build_folder -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kr260_som:part0:1.1 [current_project]
add_files [list [file normalize [file join $rtl_folder ddr_latency_tester.v]]]   ;# list: path has a space

create_bd_design system

# --- Zynq processing system: board preset, only HP0 enabled ------------------
set zynq [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e zynq]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $zynq
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0         {0} \
    CONFIG.PSU__USE__M_AXI_GP1         {0} \
    CONFIG.PSU__USE__M_AXI_GP2         {0} \
    CONFIG.PSU__USE__S_AXI_GP2         {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH    {128} \
    CONFIG.PSU__FPGA_PL0_ENABLE        {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $zynq

# --- Test clock: 100 MHz pl_clk0 -> TEST_CLOCK_MHZ ---------------------------
# The input frequency is taken from pl_clk0 (really 99.999 MHz), not typed in.
set clock_wizard [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clock_wizard]
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  $test_clock_mhz \
    CONFIG.USE_RESET                   {false} \
    CONFIG.USE_LOCKED                  {false} \
] $clock_wizard
connect_bd_net [get_bd_pins zynq/pl_clk0] [get_bd_pins clock_wizard/clk_in1]
set test_clock [get_bd_pins clock_wizard/clk_out1]

# --- DDR tester ---------------------------------------------------------------
set tester [create_bd_cell -type module -reference ddr_latency_tester tester]
connect_bd_intf_net [get_bd_intf_pins tester/m_axi] [get_bd_intf_pins zynq/S_AXI_HP0_FPD]
connect_bd_net $test_clock [get_bd_pins tester/clock] [get_bd_pins zynq/saxihp0_fpd_aclk]

# --- VIO: 2 outputs (reset, start), 6 inputs (results) -----------------------
set vio [create_bd_cell -type ip -vlnv xilinx.com:ip:vio vio]
set_property -dict [list \
    CONFIG.C_NUM_PROBE_OUT      {2} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {1} \
    CONFIG.C_NUM_PROBE_IN       {6} \
    CONFIG.C_PROBE_IN0_WIDTH    {1} \
    CONFIG.C_PROBE_IN1_WIDTH    {1} \
    CONFIG.C_PROBE_IN2_WIDTH    {32} \
    CONFIG.C_PROBE_IN3_WIDTH    {64} \
    CONFIG.C_PROBE_IN4_WIDTH    {64} \
    CONFIG.C_PROBE_IN5_WIDTH    {128} \
] $vio
connect_bd_net $test_clock [get_bd_pins vio/clk]
connect_bd_net [get_bd_pins vio/probe_out0] [get_bd_pins tester/reset]
connect_bd_net [get_bd_pins vio/probe_out1] [get_bd_pins tester/start]
connect_bd_net [get_bd_pins tester/done]           [get_bd_pins vio/probe_in0]
connect_bd_net [get_bd_pins tester/timed_out]      [get_bd_pins vio/probe_in1]
connect_bd_net [get_bd_pins tester/error_count]    [get_bd_pins vio/probe_in2]
connect_bd_net [get_bd_pins tester/minimum_cycles] [get_bd_pins vio/probe_in3]
connect_bd_net [get_bd_pins tester/maximum_cycles] [get_bd_pins vio/probe_in4]
connect_bd_net [get_bd_pins tester/total_cycles]   [get_bd_pins vio/probe_in5]

# --- Addresses, checks, wrapper ------------------------------------------------
assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files system.bd] -top
add_files [list [file join $build_folder ddr_tester.gen sources_1 bd system hdl system_wrapper.v]]
set_property top system_wrapper [current_fileset]

# --- Build ----------------------------------------------------------------------
# Compress the bitstream: the design is tiny, so this shrinks the file a lot,
# which matters because it is sent to U-Boot over the 115200-baud serial port.
set compression_constraints [file join $build_folder compression.xdc]
set constraints_file [open $compression_constraints w]
puts $constraints_file {set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]}
close $constraints_file
add_files -fileset constrs_1 [list $compression_constraints]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Build failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
set setup_slack [get_property SLACK [get_timing_paths -setup -max_paths 1]]
set hold_slack  [get_property SLACK [get_timing_paths -hold  -max_paths 1]]
puts "DDR_TESTER_TIMING ${test_clock_mhz}MHz setup=$setup_slack hold=$hold_slack"

set implementation_folder [get_property DIRECTORY [get_runs impl_1]]
file copy -force [file join $implementation_folder system_wrapper.bit] [file join $script_folder ddr_tester_${test_clock_mhz}MHz.bit]
file copy -force [file join $implementation_folder system_wrapper.ltx] [file join $script_folder ddr_tester_${test_clock_mhz}MHz.ltx]
puts "DDR_TESTER_BUILT ${test_clock_mhz}MHz"
