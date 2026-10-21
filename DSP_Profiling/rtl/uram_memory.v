`timescale 1ns / 1ps
//==============================================================================
// uram_memory
//
// A memory built from one UltraRAM (URAM) block, with a separate write port
// and read port. Default size: 4096 words x 72 bits = one URAM288 block
// (URAM is always 72 bits wide, so narrower data would waste it).
//
// Write: 1 clock cycle. The word is stored at the clock edge where
//        write_enable is high, and can be read starting the next cycle.
//
// Read: READ_PIPELINE_STAGES clock cycles from read_enable to read_valid.
//   1 : data comes straight out of the URAM array
//   2 : data also passes through the URAM's output register (OREG)
//   3 : one more register after that
// More stages = shorter paths, so it can run at a faster clock.
//==============================================================================
module uram_memory #(
    parameter DATA_WIDTH           = 72,
    parameter ADDRESS_WIDTH        = 12,   // 2^12 = 4096 words
    parameter READ_PIPELINE_STAGES = 1     // 1, 2 or 3
)(
    input  wire                     clock,

    // Write port
    input  wire                     write_enable,
    input  wire [ADDRESS_WIDTH-1:0] write_address,
    input  wire [DATA_WIDTH-1:0]    write_data,

    // Read port
    input  wire                     read_enable,
    input  wire [ADDRESS_WIDTH-1:0] read_address,
    output wire                     read_valid,   // high when read_data holds the requested word
    output wire [DATA_WIDTH-1:0]    read_data
);
    //--------------------------------------------------------------------------
    // The memory array (Vivado builds it as an UltraRAM)
    //--------------------------------------------------------------------------
    (* ram_style = "ultra" *)
    reg [DATA_WIDTH-1:0] memory [0:(1 << ADDRESS_WIDTH) - 1];

    always @(posedge clock)
        if (write_enable)
            memory[write_address] <= write_data;

    //--------------------------------------------------------------------------
    // Read: the URAM's own read register, then optional extra stages
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] read_data_stage1;   // inside the URAM array
    reg [DATA_WIDTH-1:0] read_data_stage2;   // URAM output register (OREG)
    reg [DATA_WIDTH-1:0] read_data_stage3;   // one more register

    always @(posedge clock) begin
        if (read_enable)
            read_data_stage1 <= memory[read_address];
        read_data_stage2 <= read_data_stage1;
        read_data_stage3 <= read_data_stage2;
    end

    assign read_data = (READ_PIPELINE_STAGES == 3) ? read_data_stage3 :
                       (READ_PIPELINE_STAGES == 2) ? read_data_stage2 : read_data_stage1;

    //--------------------------------------------------------------------------
    // read_valid = read_enable delayed by READ_PIPELINE_STAGES cycles
    //--------------------------------------------------------------------------
    reg [READ_PIPELINE_STAGES-1:0] valid_delay_line = 0;

    always @(posedge clock)
        valid_delay_line <= (valid_delay_line << 1) | read_enable;

    assign read_valid = valid_delay_line[READ_PIPELINE_STAGES-1];
endmodule
