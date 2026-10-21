`timescale 1ns / 1ps
//==============================================================================
// bram_memory
//
// A memory built from one block RAM (BRAM) with a separate write port and
// read port, so a write and a read can happen in the same clock cycle.
// Default size: 1024 words x 18 bits = one RAMB18 block.
//
// Write: 1 clock cycle. The word is stored at the clock edge where
//        write_enable is high, and can be read starting the next cycle.
//
// Read: READ_PIPELINE_STAGES clock cycles from read_enable to read_valid.
//   1 : data comes straight out of the BRAM's memory array
//   2 : data also passes through the BRAM's built-in output register
//       (DOB_REG). Shorter paths, so it can run at a faster clock.
//==============================================================================
module bram_memory #(
    parameter DATA_WIDTH           = 18,
    parameter ADDRESS_WIDTH        = 10,   // 2^10 = 1024 words
    parameter READ_PIPELINE_STAGES = 1     // 1 or 2
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
    // The memory array (Vivado builds it as a block RAM)
    //--------------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] memory [0:(1 << ADDRESS_WIDTH) - 1];

    always @(posedge clock)
        if (write_enable)
            memory[write_address] <= write_data;

    //--------------------------------------------------------------------------
    // Read: the BRAM's own read register, plus its optional output register
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] read_data_stage1;   // inside the BRAM array
    reg [DATA_WIDTH-1:0] read_data_stage2;   // BRAM output register (DOB_REG)

    always @(posedge clock) begin
        if (read_enable)
            read_data_stage1 <= memory[read_address];
        read_data_stage2 <= read_data_stage1;
    end

    assign read_data = (READ_PIPELINE_STAGES == 2) ? read_data_stage2 : read_data_stage1;

    //--------------------------------------------------------------------------
    // read_valid = read_enable delayed by READ_PIPELINE_STAGES cycles
    //--------------------------------------------------------------------------
    reg [READ_PIPELINE_STAGES-1:0] valid_delay_line = 0;

    always @(posedge clock)
        valid_delay_line <= (valid_delay_line << 1) | read_enable;

    assign read_valid = valid_delay_line[READ_PIPELINE_STAGES-1];
endmodule
