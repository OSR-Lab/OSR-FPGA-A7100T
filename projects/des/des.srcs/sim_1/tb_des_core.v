`timescale 1ns / 1ps
// ============================================================================
// Testbench for DES Core
// Uses verified NIST / known-answer test vectors
// ============================================================================
module tb_des_core;

    // DUT signals
    reg         clk;
    reg         rst_n;
    reg         start;
    reg         enc_dec;
    reg  [63:0] key_in;
    reg  [63:0] data_in;
    wire [63:0] data_out;
    wire        done;
    wire        busy;

    // Test counters
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_num = 0;

    // Clock generation: 50 MHz (20 ns period)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // DUT instantiation
    des_core uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .enc_dec  (enc_dec),
        .key_in   (key_in),
        .data_in  (data_in),
        .data_out (data_out),
        .done     (done),
        .busy     (busy)
    );

    // ---------------------------------------------------------------
    // Task: encrypt and check
    // ---------------------------------------------------------------
    task do_encrypt;
        input [63:0] key;
        input [63:0] plaintext;
        input [63:0] expected_cipher;
        begin
            test_num = test_num + 1;
            @(posedge clk);
            enc_dec = 1'b0;
            key_in  = key;
            data_in = plaintext;
            start   = 1'b1;
            @(posedge clk);
            start   = 1'b0;
            // Wait for done
            wait (done == 1'b1);
            @(posedge clk);
            if (data_out === expected_cipher) begin
                $display("[PASS] Test %0d Encrypt: key=%h pt=%h -> ct=%h",
                         test_num, key, plaintext, data_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d Encrypt: key=%h pt=%h", test_num, key, plaintext);
                $display("       Expected: %h", expected_cipher);
                $display("       Got:      %h", data_out);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Task: decrypt and check
    // ---------------------------------------------------------------
    task do_decrypt;
        input [63:0] key;
        input [63:0] ciphertext;
        input [63:0] expected_plain;
        begin
            test_num = test_num + 1;
            @(posedge clk);
            enc_dec = 1'b1;
            key_in  = key;
            data_in = ciphertext;
            start   = 1'b1;
            @(posedge clk);
            start   = 1'b0;
            wait (done == 1'b1);
            @(posedge clk);
            if (data_out === expected_plain) begin
                $display("[PASS] Test %0d Decrypt: key=%h ct=%h -> pt=%h",
                         test_num, key, ciphertext, data_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d Decrypt: key=%h ct=%h", test_num, key, ciphertext);
                $display("       Expected: %h", expected_plain);
                $display("       Got:      %h", data_out);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Task: encrypt + decrypt round-trip
    // ---------------------------------------------------------------
    task do_roundtrip;
        input [63:0] key;
        input [63:0] plaintext;
        input [63:0] expected_cipher;
        begin
            $display("------------------------------------------------------");
            $display("Key = %h", key);
            do_encrypt(key, plaintext, expected_cipher);
            do_decrypt(key, expected_cipher, plaintext);
        end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        // Initialize
        rst_n   = 1'b0;
        start   = 1'b0;
        enc_dec = 1'b0;
        key_in  = 64'h0;
        data_in = 64'h0;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        $display("======================================================");
        $display("DES Core Testbench Start");
        $display("======================================================");

        // ----- Test Vector 1: FIPS 46-3 Appendix B -----
        // Key: 133457799BBCDFF1  Plaintext: 0123456789ABCDEF
        // Expected: 85E813540F0AB405
        do_roundtrip(
            64'h133457799BBCDFF1,
            64'h0123456789ABCDEF,
            64'h85E813540F0AB405
        );

        // ----- Test Vector 2: All zeros -----
        do_roundtrip(
            64'h0000000000000000,
            64'h0000000000000000,
            64'h8CA64DE9C1B123A7
        );

        // ----- Test Vector 3: All ones -----
        do_roundtrip(
            64'hFFFFFFFFFFFFFFFF,
            64'hFFFFFFFFFFFFFFFF,
            64'h7359B2163E4EDC58
        );

        // ----- Test Vector 4: FIPS PUB 81 -----
        do_roundtrip(
            64'h0123456789ABCDEF,
            64'h4E6F772069732074,
            64'h3FA40E8A984D4815
        );

        // ----- Test Vector 5 -----
        do_roundtrip(
            64'h0123456789ABCDEF,
            64'h0000000000000000,
            64'hD5D44FF720683D0D
        );

        // ----- Test Vector 6 -----
        do_roundtrip(
            64'h1111111111111111,
            64'h1111111111111111,
            64'hF40379AB9E0EC533
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
        #1_000_000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
