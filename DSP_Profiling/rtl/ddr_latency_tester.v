`timescale 1ns / 1ps
//==============================================================================
// ddr_latency_tester
//
// Measures how many clock cycles DDR reads and writes take when the FPGA
// reaches the KR260's DDR4 through the Zynq's HP0 port (AXI4, 128 bits).
//
// It runs 4 tests, one transaction at a time (never two in flight):
//   test 0: single write  (1 beat  = 16 bytes)  request -> write response
//   test 1: single read   (1 beat  = 16 bytes)  request -> data
//   test 2: burst write   (16 beats = 256 bytes) request -> write response
//   test 3: burst read    (16 beats = 256 bytes) request -> last data beat
// Each test does TRANSFERS_PER_TEST transactions and keeps the minimum,
// maximum and total cycle count, so average = total / TRANSFERS_PER_TEST.
//
// How a transaction is timed: the cycle counter starts at 0 on the clock edge
// that raises the request (AWVALID/ARVALID), and "cycles" is the number of
// edges until the edge where the response is received.
//
// Test data: every 32-bit word written holds its own byte address, so reads
// can be checked, and the DDR contents can be checked from U-Boot (md command).
//==============================================================================
module ddr_latency_tester #(
    parameter [48:0] BASE_ADDRESS       = 49'h0_4000_0000,   // free DDR region
    parameter        TRANSFERS_PER_TEST = 64,
    parameter        BURST_BEATS        = 16,
    parameter        TIMEOUT_CYCLES     = 100000
)(
    // These attributes tell Vivado's block design that m_axi runs on "clock"
    // and that "reset" is active high. They don't change the logic.
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clock CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET reset" *)
    input  wire         clock,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 reset RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire         reset,          // active high
    input  wire         start,          // rising edge starts all 4 tests

    // Results
    output reg          done,           // all tests finished
    output reg          timed_out,      // a transaction never finished
    output reg  [31:0]  error_count,    // wrong read data or error responses
    output wire [63:0]  minimum_cycles, // 4 x 16 bits, test 0 in the low bits
    output wire [63:0]  maximum_cycles, // 4 x 16 bits
    output wire [127:0] total_cycles,   // 4 x 32 bits

    // AXI4 master -> Zynq HP0 (S_AXI_HP0_FPD)
    output wire [5:0]   m_axi_awid,
    output reg  [48:0]  m_axi_awaddr,
    output reg  [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awlock,
    output wire [3:0]   m_axi_awcache,
    output wire [2:0]   m_axi_awprot,
    output wire [3:0]   m_axi_awqos,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,

    output reg  [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,

    input  wire [5:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,

    output wire [5:0]   m_axi_arid,
    output reg  [48:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arlock,
    output wire [3:0]   m_axi_arcache,
    output wire [2:0]   m_axi_arprot,
    output wire [3:0]   m_axi_arqos,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,

    input  wire [5:0]   m_axi_rid,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready
);
    //--------------------------------------------------------------------------
    // Fixed AXI settings: 16-byte beats, incrementing bursts, plain accesses
    //--------------------------------------------------------------------------
    assign m_axi_awid    = 6'd0;
    assign m_axi_awsize  = 3'd4;        // 2^4 = 16 bytes per beat
    assign m_axi_awburst = 2'b01;       // INCR
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;     // normal, bufferable
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'd0;
    assign m_axi_wstrb   = 16'hFFFF;    // write all 16 bytes
    assign m_axi_bready  = 1'b1;        // always accept write responses

    assign m_axi_arid    = 6'd0;
    assign m_axi_arsize  = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'd0;
    assign m_axi_rready  = 1'b1;        // always accept read data

    //--------------------------------------------------------------------------
    // Tests
    //--------------------------------------------------------------------------
    localparam TEST_SINGLE_WRITE = 2'd0,
               TEST_SINGLE_READ  = 2'd1,
               TEST_BURST_WRITE  = 2'd2,
               TEST_BURST_READ   = 2'd3;

    // Singles use addresses BASE, BASE+16, ...; bursts start 64 KB higher,
    // 256 bytes apart (a burst never crosses a 4 KB boundary).
    localparam [48:0] BURST_REGION_OFFSET = 49'h1_0000;

    reg  [1:0]  test;                 // which test is running
    reg  [15:0] transfer;             // transaction number within the test
    reg  [7:0]  beat;                 // beat number within the transaction
    reg  [31:0] cycle_counter;        // cycles since the request was raised

    wire        is_write_test = (test == TEST_SINGLE_WRITE) || (test == TEST_BURST_WRITE);
    wire        is_burst_test = (test == TEST_BURST_WRITE)  || (test == TEST_BURST_READ);
    wire [7:0]  beats_minus_1 = is_burst_test ? BURST_BEATS - 1 : 8'd0;   // AXI "len" field

    wire [48:0] transaction_address =
        is_burst_test ? BASE_ADDRESS + BURST_REGION_OFFSET + transfer * (BURST_BEATS * 16)
                      : BASE_ADDRESS + transfer * 16;

    // Test data for one 16-byte beat: each 32-bit word = its own byte address
    function [127:0] data_for_address(input [48:0] beat_address);
        data_for_address = { beat_address[31:0] + 32'd12, beat_address[31:0] + 32'd8,
                             beat_address[31:0] + 32'd4,  beat_address[31:0] };
    endfunction

    wire [48:0] current_beat_address = transaction_address + beat * 16;

    //--------------------------------------------------------------------------
    // Statistics: one min/max/total per test
    //--------------------------------------------------------------------------
    reg [15:0] minimum [0:3];
    reg [15:0] maximum [0:3];
    reg [31:0] total   [0:3];

    assign minimum_cycles = {minimum[3], minimum[2], minimum[1], minimum[0]};
    assign maximum_cycles = {maximum[3], maximum[2], maximum[1], maximum[0]};
    assign total_cycles   = {total[3],   total[2],   total[1],   total[0]};

    //--------------------------------------------------------------------------
    // State machine
    //--------------------------------------------------------------------------
    localparam [1:0] STATE_IDLE  = 2'd0,   // wait for start
                     STATE_ISSUE = 2'd1,   // raise the request for one transaction
                     STATE_WAIT  = 2'd2,   // move data, wait for the response
                     STATE_DONE  = 2'd3;

    reg [1:0] state;
    reg       start_previous;
    integer   i;

    // Cycle count if the transaction finishes at this clock edge
    wire [31:0] cycles_so_far = cycle_counter + 1;

    // The response that ends a transaction: write response, or last read beat
    wire transaction_finishing = m_axi_bvalid || (m_axi_rvalid && m_axi_rlast);

    always @(posedge clock) begin
        if (reset) begin
            state          <= STATE_IDLE;
            start_previous <= 1'b0;
            done           <= 1'b0;
            timed_out      <= 1'b0;
            error_count    <= 0;
            m_axi_awvalid  <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_arvalid  <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                minimum[i] <= 16'hFFFF;
                maximum[i] <= 16'h0000;
                total[i]   <= 32'd0;
            end
        end else begin
            start_previous <= start;

            case (state)
            //------------------------------------------------------------------
            STATE_IDLE: begin
                if (start && !start_previous) begin   // rising edge of start
                    test     <= TEST_SINGLE_WRITE;
                    transfer <= 0;
                    state    <= STATE_ISSUE;
                end
            end

            //------------------------------------------------------------------
            STATE_ISSUE: begin
                beat          <= 0;
                cycle_counter <= 0;
                if (is_write_test) begin
                    m_axi_awaddr  <= transaction_address;
                    m_axi_awlen   <= beats_minus_1;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata   <= data_for_address(transaction_address);
                    m_axi_wlast   <= (beats_minus_1 == 0);
                    m_axi_wvalid  <= 1'b1;
                end else begin
                    m_axi_araddr  <= transaction_address;
                    m_axi_arlen   <= beats_minus_1;
                    m_axi_arvalid <= 1'b1;
                end
                state <= STATE_WAIT;
            end

            //------------------------------------------------------------------
            STATE_WAIT: begin
                cycle_counter <= cycles_so_far;

                // Address accepted
                if (m_axi_awvalid && m_axi_awready) m_axi_awvalid <= 1'b0;
                if (m_axi_arvalid && m_axi_arready) m_axi_arvalid <= 1'b0;

                // Write data: send the next beat after each accepted one
                if (m_axi_wvalid && m_axi_wready) begin
                    if (m_axi_wlast) begin
                        m_axi_wvalid <= 1'b0;
                    end else begin
                        beat        <= beat + 1;
                        m_axi_wdata <= data_for_address(current_beat_address + 16);
                        m_axi_wlast <= (beat + 1 == beats_minus_1);
                    end
                end

                // Write response: check it is OKAY
                if (m_axi_bvalid && m_axi_bresp != 2'b00)
                    error_count <= error_count + 1;

                // Read data: check every beat against the expected pattern
                if (m_axi_rvalid) begin
                    if (m_axi_rdata != data_for_address(current_beat_address) || m_axi_rresp != 2'b00)
                        error_count <= error_count + 1;
                    beat <= beat + 1;
                end

                // Record the cycle count and move to the next transaction
                if (transaction_finishing) begin
                    if (cycles_so_far < minimum[test]) minimum[test] <= cycles_so_far;
                    if (cycles_so_far > maximum[test]) maximum[test] <= cycles_so_far;
                    total[test] <= total[test] + cycles_so_far;

                    if (transfer == TRANSFERS_PER_TEST - 1) begin
                        transfer <= 0;
                        if (test == TEST_BURST_READ) state <= STATE_DONE;
                        else begin
                            test  <= test + 1;
                            state <= STATE_ISSUE;
                        end
                    end else begin
                        transfer <= transfer + 1;
                        state    <= STATE_ISSUE;
                    end
                end else if (cycles_so_far >= TIMEOUT_CYCLES) begin
                    timed_out <= 1'b1;
                    state     <= STATE_DONE;
                end
            end

            //------------------------------------------------------------------
            STATE_DONE: done <= 1'b1;
            endcase
        end
    end
endmodule
