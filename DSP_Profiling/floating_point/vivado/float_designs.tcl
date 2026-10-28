# ==============================================================================
# float_designs.tcl
#
# The floating-point designs to simulate and build, shared by
# run_float_simulation.tcl and run_float_profile.tcl.
#
# Each row:
#   name  harness_unit  test_code  ip_operation  precision  latency  [seed_bits  iterations]
#     harness_unit : float_timing_harness UNIT (0 = IP, 1 = power, 2/3/4 = current design,
#                    5 = IP reciprocal, 6 = Newton-Raphson reciprocal)
#     test_code    : tb_float_profile OPERATION_CODE
#     ip_operation : Add_Subtract / Multiply / Divide / Reciprocal, or "-" (no IP needed)
#     precision    : Half (16-bit) or Single (32-bit)
#     latency      : IP pipeline stages (1 for the current design;
#                    stages per multiply for the Newton-Raphson reciprocal)
#     seed_bits, iterations : Newton-Raphson reciprocal only
#
# Stage options per IP operation: 1, about halfway, and the IP's maximum
# (add 11, multiply 8 half / 6 single, divide 15 half / 28 single,
# reciprocal 4 half / 29 single). Newton-Raphson reciprocal: 1-3 stages per
# multiply, for two seed-table / iteration settings per precision.
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
    {reciprocal_ip_half_1   5  7  Reciprocal    Half    1}
    {reciprocal_ip_half_2   5  7  Reciprocal    Half    2}
    {reciprocal_ip_half_4   5  7  Reciprocal    Half    4}
    {reciprocal_ip_single_1  5 7  Reciprocal    Single  1}
    {reciprocal_ip_single_15 5 7  Reciprocal    Single 15}
    {reciprocal_ip_single_29 5 7  Reciprocal    Single 29}
    {reciprocal_nr_half_seed7_1iter_1    6  8  -  Half    1  7  1}
    {reciprocal_nr_half_seed7_1iter_2    6  8  -  Half    2  7  1}
    {reciprocal_nr_half_seed7_1iter_3    6  8  -  Half    3  7  1}
    {reciprocal_nr_half_seed3_2iter_1    6  8  -  Half    1  3  2}
    {reciprocal_nr_half_seed3_2iter_2    6  8  -  Half    2  3  2}
    {reciprocal_nr_half_seed3_2iter_3    6  8  -  Half    3  3  2}
    {reciprocal_nr_single_seed7_2iter_1  6  8  -  Single  1  7  2}
    {reciprocal_nr_single_seed7_2iter_2  6  8  -  Single  2  7  2}
    {reciprocal_nr_single_seed7_2iter_3  6  8  -  Single  3  7  2}
    {reciprocal_nr_single_seed4_3iter_1  6  8  -  Single  1  4  3}
    {reciprocal_nr_single_seed4_3iter_2  6  8  -  Single  2  4  3}
    {reciprocal_nr_single_seed4_3iter_3  6  8  -  Single  3  4  3}
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
    if {$operation eq "Reciprocal"}   { lappend settings CONFIG.C_Mult_Usage Full_Usage }
    set_property -dict $settings $ip
}
