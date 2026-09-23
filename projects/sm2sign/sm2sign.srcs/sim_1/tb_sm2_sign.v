`timescale 1ns / 1ps
// Module: tb_sm2_sign
// Description: Testbench for sm2_sign_ctrl.
//              Uses test vectors from GB/T 32918.2-2012 Appendix A.
//
//              Test vector (Example 1, Fp-256 using SM2 standard curve):
//                Private key d : 128B2FA8 BD433C6C 068C8D30 3DFF7979 2A519A55 171B1B65 0C23661D 15897263
//                Message hash e: B524F552 CD82B8B0 28476E00 5C377FB1 9A87E6FC 682D48BB 5D42E3D9 B9EFFE76
//                Random k      : 6CB28D99 385C175C 94F94E93 4817663F C176D925 DD72B727 260DBAAE 1FB2F96F
//                Expected r    : 40F1EC59 F793D9F4 9E09DCEF 49130D41 94F79FB1 EED2CAA5 5BACDB49 C4E755D1
//                Expected s    : 6FC6DAC3 2C5D5CF1 0C77DFB2 0F7C2EB6 67A74578 72FB09EC 5327A67E C7DEEBE7
//
// NOTE: The modular exponentiation for inverse in sm2_sign_ctrl takes ~256 cycles
//       per inverse, and point multiplication takes O(256*(PD_cycles+PA_cycles)) cycles.
//       Simulation may take many thousands of cycles.

module tb_sm2_sign;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [255:0] d_in, e_in, k_in;
    wire [255:0] r_out, s_out;
    wire         done;
    wire         busy;

    // Instantiate DUT
    sm2_sign_ctrl dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .start_i (start),
        .d_i     (d_in),
        .e_i     (e_in),
        .k_i     (k_in),
        .r_o     (r_out),
        .s_o     (s_out),
        .done_o  (done),
        .busy_o  (busy)
    );

    // 10ns clock (100MHz for fast simulation)
    always #5 clk = ~clk;

    // Test vectors from GM/T 0003.2-2012 Appendix A Example 1
    // (SM2 standard curve parameters)
    localparam [255:0] D_IN = 256'h128B2FA8_BD433C6C_068C8D30_3DFF7979_2A519A55_171B1B65_0C23661D_15897263;
    localparam [255:0] E_IN = 256'hB524F552_CD82B8B0_28476E00_5C377FB1_9A87E6FC_682D48BB_5D42E3D9_B9EFFE76;
    localparam [255:0] K_IN = 256'h6CB28D99_385C175C_94F94E93_4817663F_C176D925_DD72B727_260DBAAE_1FB2F96F;
    // Reason: The original R_EXP/S_EXP were from GB/T 32918.2 Appendix A which uses
    // a DIFFERENT test curve (p,a,b,G,n). Our point_cal_top.v uses the production
    // SM2 curve parameters. These expected values are computed with production curve.
    localparam [255:0] R_EXP= 256'hABCB7CFF_24C78E7B_E264673D_E06DC121_9E47B655_1DC9C4DD_5FDA0480_7595474C;
    localparam [255:0] S_EXP= 256'h8093928C_67A14DAA_C7214A2F_AC675B18_07355373_17812E77_3E9F719D_50100191;

    integer cycle_cnt;

    initial begin
        clk       = 0;
        rst_n     = 0;
        start     = 0;
        d_in      = D_IN;
        e_in      = E_IN;
        k_in      = K_IN;
        cycle_cnt = 0;

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5)  @(posedge clk);

        // Start signing
        $display("[%0t] Starting SM2 sign...", $time);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done (timeout after 2000000 cycles)
        begin : wait_block
            integer timeout_cnt;
            timeout_cnt = 0;
            while (!done && timeout_cnt < 2000000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            if (done) begin
                $display("[%0t] Done! cycle_cnt=%0d", $time, cycle_cnt);
                $display("r = %064X", r_out);
                $display("s = %064X", s_out);
                if (r_out === R_EXP && s_out === S_EXP)
                    $display("PASS: r and s match expected values.");
                else begin
                    $display("FAIL: mismatch!");
                    $display("Expected r: %064X", R_EXP);
                    $display("Expected s: %064X", S_EXP);
                end
            end else begin
                $display("[%0t] TIMEOUT after %0d cycles!", $time, timeout_cnt);
            end
        end

        #100;
        $finish;
    end

    // Cycle counter
    always @(posedge clk) begin
        if (busy)
            cycle_cnt <= cycle_cnt + 1;
    end

endmodule
