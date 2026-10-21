`timescale 1ns / 1ps
//==============================================================================
// tb_ddr_latency_tester
//
// Checks ddr_latency_tester against a simple AXI memory model with a known,
// fixed delay, so every measured cycle count can be predicted exactly:
//
//   single write  = 3 + WRITE_DELAY
//   single read   = 3 + READ_DELAY
//   burst write   = 3 + WRITE_DELAY + (BURST_BEATS - 1)
//   burst read    = 3 + READ_DELAY  + (BURST_BEATS - 1)
//
// Where the 3 comes from (single write; the model accepts everything at once):
//   edge 0: tester raises AWVALID/WVALID
//   edge 1: model accepts address and data, starts its delay
//   edge 2+WRITE_DELAY: model raises BVALID
//   edge 3+WRITE_DELAY: tester sees BVALID -> transaction finished
// A burst adds one edge per extra data beat.
//
// The real DDR on the board is not this predictable; this only proves the
// tester counts and checks correctly.
//==============================================================================
module tb_ddr_latency_tester;

    localparam WRITE_DELAY        = 5;
    localparam READ_DELAY         = 9;
    localparam BURST_BEATS        = 16;
    localparam TRANSFERS_PER_TEST = 8;

    reg clock = 0;
    always #5 clock = ~clock;

    reg reset = 1;
    reg start = 0;

    //--------------------------------------------------------------------------
    // Tester
    //--------------------------------------------------------------------------
    wire         done, timed_out;
    wire [31:0]  error_count;
    wire [63:0]  minimum_cycles, maximum_cycles;
    wire [127:0] total_cycles;

    wire [48:0]  awaddr, araddr;
    wire [7:0]   awlen, arlen;
    wire         awvalid, wvalid, wlast, arvalid;
    wire [127:0] wdata;
    reg          bvalid = 0, rvalid = 0, rlast = 0;
    reg  [127:0] rdata;

    ddr_latency_tester #(
        .BASE_ADDRESS(49'h0_4000_0000),
        .TRANSFERS_PER_TEST(TRANSFERS_PER_TEST),
        .BURST_BEATS(BURST_BEATS)
    ) tester (
        .clock(clock), .reset(reset), .start(start),
        .done(done), .timed_out(timed_out), .error_count(error_count),
        .minimum_cycles(minimum_cycles), .maximum_cycles(maximum_cycles), .total_cycles(total_cycles),
        .m_axi_awid(), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(), .m_axi_awburst(),
        .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awqos(),
        .m_axi_awvalid(awvalid), .m_axi_awready(1'b1),
        .m_axi_wdata(wdata), .m_axi_wstrb(), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(1'b1),
        .m_axi_bid(6'd0), .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(),
        .m_axi_arid(), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(), .m_axi_arburst(),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arqos(),
        .m_axi_arvalid(arvalid), .m_axi_arready(1'b1),
        .m_axi_rid(6'd0), .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready());

    //--------------------------------------------------------------------------
    // AXI memory model: accepts every request immediately, answers after a
    // fixed delay. Stores 16-byte words in an array indexed by address.
    //--------------------------------------------------------------------------
    reg [127:0] memory [0:8191];
    function integer word_index(input [48:0] address);
        word_index = (address - 49'h0_4000_0000) >> 4;
    endfunction

    // Write side
    reg [48:0] write_address;
    integer    write_countdown = -1;   // -1 = no response pending

    always @(posedge clock) begin
        if (awvalid) write_address <= awaddr;           // address accepted
        if (wvalid) begin                               // data beat accepted
            memory[word_index(awvalid ? awaddr : write_address)] <= wdata;
            write_address <= (awvalid ? awaddr : write_address) + 16;
            if (wlast) write_countdown <= WRITE_DELAY;
        end
        if (write_countdown == 0) bvalid <= 1;
        if (write_countdown >= 0) write_countdown <= write_countdown - 1;
        if (bvalid) bvalid <= 0;                        // tester always ready
    end

    // Read side
    reg [48:0] read_address;
    integer    read_countdown = -1;    // -1 = not started
    integer    read_beats_left = 0;

    always @(posedge clock) begin
        rvalid <= 0;
        rlast  <= 0;
        if (arvalid) begin                              // request accepted
            read_address    <= araddr;
            read_beats_left <= arlen + 1;
            read_countdown  <= READ_DELAY;
        end else if (read_countdown > 0) begin
            read_countdown <= read_countdown - 1;
        end else if (read_countdown == 0 && read_beats_left > 0) begin
            rvalid          <= 1;                       // one beat per cycle
            // +corrupt flips one bit of every beat, to prove errors are caught
            rdata           <= memory[word_index(read_address)] ^ ($test$plusargs("corrupt") ? 128'd1 : 128'd0);
            rlast           <= (read_beats_left == 1);
            read_address    <= read_address + 16;
            read_beats_left <= read_beats_left - 1;
            if (read_beats_left == 1) read_countdown <= -1;
        end
    end

    //--------------------------------------------------------------------------
    // Run and check
    //--------------------------------------------------------------------------
    integer failure_count = 0;
    integer test;
    integer expected_cycles [0:3];
    reg [8*12-1:0] test_name [0:3];

    task check(input condition, input [8*60-1:0] description);
        if (!condition) begin
            failure_count = failure_count + 1;
            $display("  CHECK FAILED: %0s", description);
        end
    endtask

    initial begin
        expected_cycles[0] = 3 + WRITE_DELAY;
        expected_cycles[1] = 3 + READ_DELAY;
        expected_cycles[2] = 3 + WRITE_DELAY + (BURST_BEATS - 1);
        expected_cycles[3] = 3 + READ_DELAY  + (BURST_BEATS - 1);
        test_name[0] = "single write"; test_name[1] = "single read";
        test_name[2] = "burst write";  test_name[3] = "burst read";

        repeat (3) @(posedge clock);
        reset = 0;
        @(posedge clock); start = 1;

        wait (done || timed_out);
        @(posedge clock);

        check(!timed_out, "no transaction timed out");
        if ($test$plusargs("corrupt"))   // every read beat is wrong: 8 singles + 8 x 16 burst beats
            check(error_count == TRANSFERS_PER_TEST * (1 + BURST_BEATS), "every corrupted beat was counted");
        else
            check(error_count == 0, "all read data matched what was written");

        for (test = 0; test < 4; test = test + 1) begin
            $display("%-12s min %0d  max %0d  total %0d  (expected %0d each)",
                     test_name[test],
                     minimum_cycles[16*test +: 16], maximum_cycles[16*test +: 16],
                     total_cycles[32*test +: 32], expected_cycles[test]);
            check(minimum_cycles[16*test +: 16] == expected_cycles[test], "minimum == expected");
            check(maximum_cycles[16*test +: 16] == expected_cycles[test], "maximum == expected");
            check(total_cycles[32*test +: 32] == expected_cycles[test] * TRANSFERS_PER_TEST, "total == expected x transfers");
        end

        // Spot-check the data pattern: each 32-bit word holds its own address
        check(memory[0] == {32'h4000000C, 32'h40000008, 32'h40000004, 32'h40000000},
              "first written word holds its own address");

        if (failure_count == 0) $display("PASS: DDR tester counts and checks correctly");
        else                    $display("FAIL: %0d failed checks", failure_count);
        $finish;
    end

    initial begin
        #2_000_000 $display("FAIL: simulation timeout"); $finish;
    end
endmodule
