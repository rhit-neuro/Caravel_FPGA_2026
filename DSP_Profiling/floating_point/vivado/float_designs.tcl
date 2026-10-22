# ==============================================================================
# float_designs.tcl
#
# The floating-point designs to simulate and build, shared by
# run_float_simulation.tcl and run_float_profile.tcl.
#
# Each row:
#   name  harness_unit  test_code  ip_operation  precision  latency
#     harness_unit : float_timing_harness UNIT (0 = IP, 1 = power, 2/3/4 = current design)
#     test_code    : tb_float_profile OPERATION_CODE
#     ip_operation : Add_Subtract / Multiply / Divide, or "-" (no IP needed)
#     precision    : Half (16-bit) or Single (32-bit)
#     latency      : IP pipeline stages (1 for the current design)
#
# Stage options per operation: 1, about halfway, and the IP's maximum
# (add 11, multiply 8 half / 6 single, divide 15 half / 28 single).
# ==============================================================================
set float_designs {
    {add_half_1             0  0  Add_Subtract  Half    1}
    {add_half_6             0  0  Add_Subtract  Half    6}
    {add_half_11            0  0  Add_Subtract  Half   11}
    {add_single_1           0  0  Add_Subtract  Single  1}
    {add_single_6           0  0  Add_Subtract  Single  6}
    {add_single_11          0  0  Add_Subtract  Single 11}
    {multiply_half_1        0  1  Multiply      Half    1}
    {multiply_half_4        0  1  Multiply      Half    4}
    {multiply_half_8        0  1  Multiply      Half    8}
    {multiply_single_1      0  1  Multiply      Single  1}
    {multiply_single_3      0  1  Multiply      Single  3}
    {multiply_single_6      0  1  Multiply      Single  6}
    {divide_half_1          0  2  Divide        Half    1}
    {divide_half_8          0  2  Divide        Half    8}
    {divide_half_15         0  2  Divide        Half   15}
    {divide_single_1        0  2  Divide        Single  1}
    {divide_single_14       0  2  Divide        Single 14}
    {divide_single_28       0  2  Divide        Single 28}
    {power_single_1         1  3  Multiply      Single  1}
    {power_single_6         1  3  Multiply      Single  6}
    {current_add_single     2  4  -             Single  1}
    {current_multiply_single 3 5  -             Single  1}
    {current_mac_single     4  6  -             Single  1}
}

# Set up the Floating-Point IP "float_under_test" for one operation.
proc configure_float_ip {ip operation precision latency} {
    set settings [list \
        CONFIG.Operation_Type     $operation \
        CONFIG.A_Precision_Type   $precision \
        CONFIG.Flow_Control       NonBlocking \
        CONFIG.Has_RESULT_TREADY  false \
        CONFIG.Maximum_Latency    false \
        CONFIG.C_Latency          $latency]
    # Use DSPs as much as the IP allows (the divider never uses DSPs)
    if {$operation eq "Add_Subtract"} { lappend settings CONFIG.Add_Sub_Value Add CONFIG.C_Mult_Usage Full_Usage }
    if {$operation eq "Multiply"}     { lappend settings CONFIG.C_Mult_Usage Max_Usage }
    set_property -dict $settings $ip
}
