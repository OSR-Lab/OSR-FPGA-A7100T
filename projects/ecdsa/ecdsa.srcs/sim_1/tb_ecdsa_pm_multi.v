`timescale 1ns / 1ps
module tb_ecdsa_pm_multi;
    reg clk, rst_n, start;
    reg [255:0] scalar;
    wire [255:0] xj, yj, zj;
    wire done;

    localparam [255:0] GX = 256'h6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    localparam [255:0] GY = 256'h4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;
    localparam [255:0] P256 = 256'hFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;

    ecdsa_pm_ctrl U_pm (
        .clk(clk), .rst_n(rst_n), .start_i(start),
        .k_i(scalar), .base_x_i(GX), .base_y_i(GY),
        .xj_o(xj), .yj_o(yj), .zj_o(zj), .done_o(done)
    );

    always #5 clk = ~clk;

    // Expected x_aff for each k (from Python)
    task test_k;
        input [255:0] k_val;
        input [255:0] x_exp;
        begin
            scalar = k_val;
            @(posedge clk); start = 1; @(posedge clk); start = 0;
            begin : w
                integer cnt; cnt = 0;
                while (!done && cnt < 2000000) begin @(posedge clk); cnt = cnt + 1; end
            end
            if (!done) begin $display("TIMEOUT k=%0X", k_val); end
            else begin
                // Quick affine check: just display Jacobian
                $display("k=0x%0X: XJ=%064X ZJ=%064X", k_val, xj, zj);
            end
            repeat(5) @(posedge clk);
        end
    endtask

    initial begin
        clk=0; rst_n=0; start=0; scalar=0;
        repeat(10) @(posedge clk); rst_n=1;
        repeat(5) @(posedge clk);

        test_k(256'd3, 256'h5ECBE4D1A6330A44C8F7EF951D4BF165E6C6B721EFADA985FB41661BC6E7FD6C);
        test_k(256'd7, 256'h8E533B6FA0BF7B4625BB30667C01FB607EF9F8B8A80FEF5B300628703187B2A3);
        test_k(256'hFF, 256'hF44B39759A2E6DB723A6F90249972DFD08E95380F1FCA470EACD1D03E5EDF214);
        test_k(256'hDEAD, 256'h83D27AAFFBB414145C875669A251DA88E19898DCC4797BC9710268A9360F35C7);

        #100; $finish;
    end
endmodule
