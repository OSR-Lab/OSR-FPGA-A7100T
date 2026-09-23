`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_aes128
// Description:    Testbench for AES-128 ECB encrypt/decrypt core
//                 Uses NIST FIPS-197 test vectors
//////////////////////////////////////////////////////////////////////////////////
module tb_aes128;

    // DUT signals
    reg           resetn;
    reg           clock;
    reg           enc_dec;
    reg           key_exp;
    reg           start;
    wire          key_val;
    wire          text_val;
    reg  [127:0]  key_in;
    reg  [127:0]  text_in;
    wire [127:0]  text_out;
    wire          busy;

    // Test counters
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer test_num = 0;

    // Clock generation: 50 MHz (20 ns period)
    initial clock = 1'b0;
    always #10 clock = ~clock;

    // DUT instantiation
    aes128 uut (
        .resetn   (resetn),
        .clock    (clock),
        .enc_dec  (enc_dec),
        .key_exp  (key_exp),
        .start    (start),
        .key_val  (key_val),
        .text_val (text_val),
        .key_in   (key_in),
        .text_in  (text_in),
        .text_out (text_out),
        .busy     (busy)
    );

    // ---------------------------------------------------------------
    // Task: perform key expansion
    // ---------------------------------------------------------------
    task do_key_expansion;
        input [127:0] key;
        begin
            key_in  = key;
            @(posedge clock);
            key_exp = 1'b1;
            @(posedge clock);
            key_exp = 1'b0;
            // Wait for key expansion to complete
            wait (key_val == 1'b1);
            @(posedge clock);
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
            enc_dec = 1'b0;   // encrypt mode
            text_in = plaintext;
            @(posedge clock);
            start   = 1'b1;
            @(posedge clock);
            start   = 1'b0;
            // Wait for encryption to complete
            wait (text_val == 1'b1);
            @(posedge clock);
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
    // Task: perform decryption and check result
    // ---------------------------------------------------------------
    task do_decrypt;
        input [127:0] ciphertext;
        input [127:0] expected_plain;
        begin
            test_num = test_num + 1;
            enc_dec = 1'b1;   // decrypt mode
            text_in = ciphertext;
            @(posedge clock);
            start   = 1'b1;
            @(posedge clock);
            start   = 1'b0;
            // Wait for decryption to complete
            wait (text_val == 1'b1);
            @(posedge clock);
            if (text_out === expected_plain) begin
                $display("[PASS] Test %0d Decrypt: ciphertext=%h -> plaintext=%h",
                         test_num, ciphertext, text_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Test %0d Decrypt: ciphertext=%h", test_num, ciphertext);
                $display("       Expected: %h", expected_plain);
                $display("       Got:      %h", text_out);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Task: full encrypt+decrypt round-trip with a given key
    // ---------------------------------------------------------------
    task do_roundtrip;
        input [127:0] key;
        input [127:0] plaintext;
        input [127:0] expected_cipher;
        begin
            $display("------------------------------------------------------");
            $display("Key       = %h", key);

            // Key expansion
            do_key_expansion(key);

            // Encrypt
            do_encrypt(plaintext, expected_cipher);

            // Key expansion again for decrypt (need round-10 key)
            do_key_expansion(key);

            // Decrypt
            do_decrypt(expected_cipher, plaintext);
        end
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        // Initialize
        resetn  = 1'b0;
        enc_dec = 1'b0;
        key_exp = 1'b0;
        start   = 1'b0;
        key_in  = 128'h0;
        text_in = 128'h0;

        // Reset
        repeat (5) @(posedge clock);
        resetn = 1'b1;
        repeat (3) @(posedge clock);

        $display("======================================================");
        $display("AES-128 Testbench Start");
        $display("======================================================");

        // ----- Test Vector 1: NIST FIPS-197 Appendix B -----
        do_roundtrip(
            128'h2b7e151628aed2a6abf7158809cf4f3c,  // key
            128'h3243f6a8885a308d313198a2e0370734,  // plaintext
            128'h3925841d02dc09fbdc118597196a0b32   // expected ciphertext
        );

        // ----- Test Vector 2: NIST FIPS-197 Appendix C.1 -----
        do_roundtrip(
            128'h000102030405060708090a0b0c0d0e0f,  // key
            128'h00112233445566778899aabbccddeeff,  // plaintext
            128'h69c4e0d86a7b0430d8cdb78070b4c55a   // expected ciphertext
        );

        // ----- Test Vector 3: All zeros -----
        do_roundtrip(
            128'h00000000000000000000000000000000,  // key
            128'h00000000000000000000000000000000,  // plaintext
            128'h66e94bd4ef8a2c3b884cfa59ca342b2e   // expected ciphertext
        );

        // ----- Test Vector 4: All ones key -----
        do_roundtrip(
            128'hffffffffffffffffffffffffffffffff,  // key
            128'h00000000000000000000000000000000,  // plaintext
            128'ha1f6258c877d5fcd8964484538bfc92c   // expected ciphertext
        );

        // ----- Test Vector 5: Multiple encryptions with same key -----
        $display("------------------------------------------------------");
        $display("Test: Multiple blocks with same key (no re-expansion)");
        do_key_expansion(128'h2b7e151628aed2a6abf7158809cf4f3c);

        do_encrypt(
            128'h3243f6a8885a308d313198a2e0370734,
            128'h3925841d02dc09fbdc118597196a0b32
        );
        do_encrypt(
            128'h6bc1bee22e409f96e93d7e117393172a,
            128'h3ad77bb40d7a3660a89ecaf32466ef97
        );
        do_encrypt(
            128'hae2d8a571e03ac9c9eb76fac45af8e51,
            128'hf5d3d58503b9699de785895a96fdbaaf
        );
        do_encrypt(
            128'h30c81c46a35ce411e5fbc1191a0a52ef,
            128'h43b1cd7f598ece23881b00e3ed030688
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
