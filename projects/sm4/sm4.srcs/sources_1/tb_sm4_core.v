`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_sm4_core
// Description:    Testbench for SM4-128 encryption core
//                 Uses GB/T 32907-2016 standard test vector
//
// Note: sm4_core uses rising-edge detection for key_exp and level detection
//       for start. Drive stimulus at @(negedge clk) to guarantee setup time
//       before the next posedge, avoiding Verilog active-region races.
//////////////////////////////////////////////////////////////////////////////////
module tb_sm4_core;

    // DUT signals
    reg           clk;
    reg           reset_n;
    reg           key_exp;
    reg           start;
    reg  [127:0]  key_in;
    reg  [127:0]  text_in;
    wire [127:0]  text_out;
    wire          key_val;
    wire          text_val;
    wire          busy;

    // Test counters
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_num = 0;

    // 50MHz clock: period = 20ns
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // DUT instantiation
    sm4_core uut (
        .clk     (clk),
        .reset_n (reset_n),
        .key_exp (key_exp),
        .start   (start),
        .key_val (key_val),
        .text_val(text_val),
        .key_in  (key_in),
        .text_in (text_in),
        .text_out(text_out),
        .busy    (busy)
    );

    // ---------------------------------------------------------------
    // Task: perform key expansion
    // ---------------------------------------------------------------
    task do_key_expansion;
        input [127:0] key;
        begin
            key_in = key;
            @(negedge clk); key_exp = 1'b1;  // drive at mid-cycle
            @(negedge clk); key_exp = 1'b0;  // clear at mid-cycle
            wait (key_val == 1'b1);
            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------
    // Task: perform encryption and check result
    // ---------------------------------------------------------------
    task do_encrypt;
        input [127:0] plaintext;
        input [127:0] expected_cipher;
        begin
            test_num = test_num + 1;
            text_in = plaintext;
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            wait (text_val == 1'b1);
            @(posedge clk);
            if (text_out === expected_cipher) begin
                $display("[PASS] Test %0d Encrypt: plaintext=%h -> ciphertext=%h",
                         test_num, plaintext, text_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d Encrypt: plaintext=%h", test_num, plaintext);
                $display("       Expected: %h", expected_cipher);
                $display("       Got:      %h", text_out);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        // Initialize
        reset_n = 1'b0;
        key_exp = 1'b0;
        start   = 1'b0;
        key_in  = 128'h0;
        text_in = 128'h0;

        // Reset: hold low for 5 cycles, release at negedge
        repeat (5) @(posedge clk);
        @(negedge clk); reset_n = 1'b1;
        repeat (3) @(posedge clk);

        $display("======================================================");
        $display("SM4-128 Core Testbench Start");
        $display("======================================================");

        // ----- Test Vector 1: GB/T 32907-2016 Appendix A.1 -----
        $display("------------------------------------------------------");
        $display("Key = 0123456789ABCDEFFEDCBA9876543210");
        do_key_expansion(128'h0123456789ABCDEFFEDCBA9876543210);

        do_encrypt(
            128'h0123456789ABCDEFFEDCBA9876543210,
            128'h681EDF34D206965E86B3E94F536E4246
        );

        // ----- Test Vector 2: Multiple blocks with same key -----
        $display("------------------------------------------------------");
        $display("Test: Multiple blocks with same key (no re-expansion)");

        do_encrypt(
            128'h0123456789ABCDEFFEDCBA9876543210,
            128'h681EDF34D206965E86B3E94F536E4246
        );

        do_encrypt(
            128'h681EDF34D206965E86B3E94F536E4246,
            128'hF324184F3C8892B72BDC9D7C612919DE
        );

        // ----- Test Vector 3: New key -----
        $display("------------------------------------------------------");
        $display("Key = FEDCBA98765432100123456789ABCDEF");
        do_key_expansion(128'hFEDCBA98765432100123456789ABCDEF);

        do_encrypt(
            128'h000102030405060708090A0B0C0D0E0F,
            128'hF766678F13F01ADEAC1B3EA955ADB594
        );

        // Summary
        $display("======================================================");
        $display("Test Summary: %0d passed, %0d failed out of %0d tests",
                 pass_cnt, fail_cnt, test_num);
        if (fail_cnt == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");
        $display("======================================================");

        #100;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #5_000_000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
