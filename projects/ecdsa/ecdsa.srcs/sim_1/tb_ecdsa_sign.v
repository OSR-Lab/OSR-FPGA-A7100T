`timescale 1ns / 1ps
// Testbench for ecdsa_sign_ctrl (NIST P-256 ECDSA signature)

module tb_ecdsa_sign;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [255:0] d_in, e_in, k_in;
    wire [255:0] r_out, s_out;
    wire         done, busy;

    ecdsa_sign_ctrl dut (
        .clk(clk), .rst_n(rst_n), .start_i(start),
        .d_i(d_in), .e_i(e_in), .k_i(k_in),
        .r_o(r_out), .s_o(s_out), .done_o(done), .busy_o(busy)
    );

    always #5 clk = ~clk;

    // Test vector: P-256, SHA-256("sample")
    localparam [255:0] D_IN  = 256'hC9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721;
    localparam [255:0] E_IN  = 256'hAF2BDBE1AA9B6EC1E2ADE1D694F41FC71A831D0268E9891562113D8A62ADD1BF;
    localparam [255:0] K_IN  = 256'hA6E3C57DD01ABE90086538398355DD4C3B17AA873382B0F24D6129493D8AAD60;
    localparam [255:0] R_EXP = 256'hEFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716;
    localparam [255:0] S_EXP = 256'hF7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8;

    integer cycle_cnt;

    initial begin
        clk = 0; rst_n = 0; start = 0;
        d_in = D_IN; e_in = E_IN; k_in = K_IN;
        cycle_cnt = 0;

        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        $display("[%0t] Starting ECDSA P-256 sign...", $time);
        start = 1; @(posedge clk); start = 0;

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
                    $display("PASS: ECDSA signature matches expected values.");
                else begin
                    $display("FAIL: mismatch!");
                    $display("Expected r: %064X", R_EXP);
                    $display("Expected s: %064X", S_EXP);
                end
            end else $display("[%0t] TIMEOUT!", $time);
        end

        #100; $finish;
    end

    always @(posedge clk) if (busy) cycle_cnt <= cycle_cnt + 1;

endmodule
