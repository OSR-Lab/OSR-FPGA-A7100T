`timescale 1ns / 1ps
// Module: ecdsa_sign_ctrl
// Description: ECDSA digital signature controller for NIST P-256.
//              Uses hardware Karatsuba multiplier + fast mod-p reduction.
//
//              ECDSA Sign (FIPS 186-4):
//                1. (x1, y1) = k * G
//                2. r = x1 mod n
//                3. s = k^{-1} * (e + r*d) mod n
//
//              Differences from SM2:
//                SM2: r = (e+x1)%n,  s = (1+d)^{-1} * (k-r*d) %n
//                ECDSA: r = x1%n,    s = k^{-1}     * (e+r*d) %n

module ecdsa_sign_ctrl (
    input           clk,
    input           rst_n,

    input           start_i,
    input  [255:0]  d_i,
    input  [255:0]  e_i,
    input  [255:0]  k_i,

    output reg [255:0] r_o,
    output reg [255:0] s_o,
    output reg         done_o,
    output             busy_o
);

// NIST P-256 parameters
localparam [255:0] P256 = 256'hFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
localparam [255:0] N256 = 256'hFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
localparam [255:0] GX   = 256'h6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
localparam [255:0] GY   = 256'h4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

// -----------------------------------------------------------------------
// Point multiplication: k * G
// -----------------------------------------------------------------------
reg         pm_start;
wire [255:0] pm_xj, pm_yj, pm_zj;
wire         pm_done;

ecdsa_pm_ctrl U_pm (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_i  (pm_start),
    .k_i      (k_i),
    .base_x_i (GX),
    .base_y_i (GY),
    .xj_o     (pm_xj),
    .yj_o     (pm_yj),
    .zj_o     (pm_zj),
    .done_o   (pm_done)
);

// -----------------------------------------------------------------------
// Hardware: Karatsuba multiplier + fast mod-p + sequential mod-n
// -----------------------------------------------------------------------
reg  [255:0] mm_a, mm_b;
reg          mul_vld;
wire         mul_fin;
wire [511:0] mul_product;

mul_ko_256b U_mul (
    .clk(clk), .rst_n(rst_n),
    .mul_vld_i(mul_vld), .mul_a_i(mm_a), .mul_b_i(mm_b),
    .mul_fin_o(mul_fin), .mul_r_o(mul_product)
);

reg          modp_vld;
wire         modp_fin;
wire [255:0] modp_result;

spd_mod_sub U_modp (
    .clk(clk), .rst_n(rst_n),
    .mod_vld_i(modp_vld), .p512_a(mul_product),
    .mod_fin_o(modp_fin), .p256_b(modp_result)
);

reg          modn_start;
wire         modn_done;
wire [255:0] modn_result;

mod_n_reduce U_modn (
    .clk(clk), .rst_n(rst_n),
    .start(modn_start), .dividend(mul_product),
    .done(modn_done), .remainder(modn_result)
);

// -----------------------------------------------------------------------
// Combinational mod add/sub
// -----------------------------------------------------------------------
function [255:0] mod_add;
    input [255:0] a, b, m;
    reg [256:0] s;
    begin
        s = {1'b0, a} + {1'b0, b};
        mod_add = (s >= {1'b0, m}) ? s[255:0] - m : s[255:0];
    end
endfunction

function [255:0] mod_sub;
    input [255:0] a, b, m;
    begin
        mod_sub = (a >= b) ? (a - b) : (a + m - b);
    end
endfunction

// -----------------------------------------------------------------------
// FSM
// -----------------------------------------------------------------------
// ECDSA sign flow:
//   1. k*G → Jacobian (XJ,YJ,ZJ)
//   2. Fermat: Z^(p-2) mod p → zj_inv
//   3. x1 = XJ * zj_inv^2 mod p (Jacobian→affine)
//   4. r = x1 mod n (just reduce if x1 >= n)
//   5. Fermat: k^(n-2) mod n → k_inv
//   6. tmp = r*d mod n
//   7. tmp = (e + tmp) mod n
//   8. s = k_inv * tmp mod n

localparam [4:0]
    S_IDLE       = 5'd0,
    S_PM         = 5'd1,
    // Fermat loop (shared)
    S_FE_CMUL    = 5'd2,
    S_FE_CMUL_MW = 5'd3,
    S_FE_CMUL_RD = 5'd4,
    S_FE_CMUL_RW = 5'd5,
    S_FE_SQ      = 5'd6,
    S_FE_SQ_MW   = 5'd7,
    S_FE_SQ_RD   = 5'd8,
    S_FE_SQ_RW   = 5'd9,
    // Affine conversion
    S_ZINV_SQ    = 5'd10,
    S_ZINV_SQ_MW = 5'd11,
    S_ZINV_SQ_RD = 5'd12,
    S_ZINV_SQ_RW = 5'd13,
    S_X1AFF      = 5'd14,
    S_X1AFF_MW   = 5'd15,
    S_X1AFF_RD   = 5'd16,
    S_X1AFF_RW   = 5'd17,
    S_CALC_R     = 5'd18,
    // Signature
    S_RD         = 5'd19,
    S_RD_MW      = 5'd20,
    S_RD_RED     = 5'd21,
    S_RD_RW      = 5'd22,
    S_CALC_ERD   = 5'd23,
    S_CALC_S     = 5'd24,
    S_CALC_S_MW  = 5'd25,
    S_CALC_S_RED = 5'd26,
    S_CALC_S_RW  = 5'd27,
    S_DONE       = 5'd28;

reg [4:0] state;

reg [255:0] d_latch, e_latch, k_latch;
reg [255:0] xj_latch, zj_latch;
reg [255:0] x1_aff, r_tmp, tmp1, tmp2;

// Fermat inverse registers
reg [255:0] fe_result, fe_base, fe_exp;
reg [8:0]   fe_cnt;
reg         fe_modn;    // 0=mod p, 1=mod n
reg [4:0]   fe_ret;     // return state

assign busy_o = (state != S_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE; pm_start <= 0; done_o <= 0;
        mul_vld <= 0; modp_vld <= 0; modn_start <= 0;
        r_o <= 0; s_o <= 0;
    end else begin
        pm_start <= 0; done_o <= 0;
        mul_vld <= 0; modp_vld <= 0; modn_start <= 0;

        case (state)
            S_IDLE: begin
                if (start_i) begin
                    d_latch <= d_i; e_latch <= e_i; k_latch <= k_i;
                    pm_start <= 1; state <= S_PM;
                end
            end

            S_PM: begin
                if (pm_done) begin
                    $display("[%0t] PM done XJ=%064X ZJ=%064X", $time, pm_xj, pm_zj);
                    xj_latch <= pm_xj; zj_latch <= pm_zj;
                    // Fermat-1: Z^(p-2) mod p
                    fe_base <= pm_zj; fe_result <= 256'd1;
                    fe_exp <= P256 - 256'd2;
                    fe_cnt <= 0; fe_modn <= 0; fe_ret <= S_ZINV_SQ;
                    state <= S_FE_CMUL;
                end
            end

            // ===== Fermat inverse loop =====
            S_FE_CMUL: begin
                if (fe_exp[0]) begin
                    mm_a <= fe_result; mm_b <= fe_base;
                    mul_vld <= 1; state <= S_FE_CMUL_MW;
                end else state <= S_FE_SQ;
            end
            S_FE_CMUL_MW: begin
                if (mul_fin) begin
                    if (!fe_modn) begin modp_vld <= 1; end
                    else               begin modn_start <= 1; end
                    state <= S_FE_CMUL_RD;
                end
            end
            S_FE_CMUL_RD: state <= S_FE_CMUL_RW;
            S_FE_CMUL_RW: begin
                if ((!fe_modn && modp_fin) || (fe_modn && modn_done)) begin
                    fe_result <= fe_modn ? modn_result : modp_result;
                    state <= S_FE_SQ;
                end
            end

            S_FE_SQ: begin
                mm_a <= fe_base; mm_b <= fe_base;
                mul_vld <= 1; state <= S_FE_SQ_MW;
            end
            S_FE_SQ_MW: begin
                if (mul_fin) begin
                    if (!fe_modn) begin modp_vld <= 1; end
                    else               begin modn_start <= 1; end
                    state <= S_FE_SQ_RD;
                end
            end
            S_FE_SQ_RD: state <= S_FE_SQ_RW;
            S_FE_SQ_RW: begin
                if ((!fe_modn && modp_fin) || (fe_modn && modn_done)) begin
                    fe_base <= fe_modn ? modn_result : modp_result;
                    fe_exp <= {1'b0, fe_exp[255:1]};
                    fe_cnt <= fe_cnt + 1;
                    state <= (fe_cnt == 9'd255) ? fe_ret : S_FE_CMUL;
                end
            end

            // ===== Jacobian -> Affine =====
            S_ZINV_SQ:    begin $display("[%0t] ZJ_inv=%064X", $time, fe_result); mm_a<=fe_result; mm_b<=fe_result; mul_vld<=1; state<=S_ZINV_SQ_MW; end
            S_ZINV_SQ_MW: begin if(mul_fin) begin modp_vld<=1; state<=S_ZINV_SQ_RD; end end
            S_ZINV_SQ_RD: state <= S_ZINV_SQ_RW;
            S_ZINV_SQ_RW: begin if(modp_fin) begin $display("[%0t] zinv_sq=%064X", $time, modp_result); tmp1<=modp_result; state<=S_X1AFF; end end

            S_X1AFF:    begin mm_a<=xj_latch; mm_b<=tmp1; mul_vld<=1; state<=S_X1AFF_MW; end
            S_X1AFF_MW: begin if(mul_fin) begin modp_vld<=1; state<=S_X1AFF_RD; end end
            S_X1AFF_RD: state <= S_X1AFF_RW;
            S_X1AFF_RW: begin if(modp_fin) begin $display("[%0t] x1_aff=%064X", $time, modp_result); x1_aff<=modp_result; state<=S_CALC_R; end end

            // ===== ECDSA: r = x1 mod n =====
            S_CALC_R: begin
                r_tmp <= (x1_aff >= N256) ? (x1_aff - N256) : x1_aff;
                $display("[%0t] CALC_R: x1_aff=%064X", $time, x1_aff);
                fe_base <= k_latch; fe_result <= 256'd1;
                fe_exp <= N256 - 256'd2;
                fe_cnt <= 0; fe_modn <= 1; fe_ret <= S_RD;
                state <= S_FE_CMUL;
            end

            // ===== ECDSA: s = k^{-1} * (e + r*d) mod n =====
            S_RD: begin
                $display("[%0t] k_inv=%064X r=%064X", $time, fe_result, r_tmp);
                tmp1 <= fe_result;     // k^{-1} mod n
                r_o  <= r_tmp;
                mm_a <= r_tmp; mm_b <= d_latch;
                mul_vld <= 1; state <= S_RD_MW;
            end
            S_RD_MW: begin if(mul_fin) begin modn_start<=1; state<=S_RD_RED; end end
            S_RD_RED: state <= S_RD_RW;
            S_RD_RW: begin
                if (modn_done) begin
                    // tmp2 = r*d mod n
                    // Reason: ECDSA uses (e + r*d), not (k - r*d) like SM2
                    tmp2 <= mod_add(e_latch, modn_result, N256);
                    state <= S_CALC_S;
                end
            end

            // s = k_inv * (e + r*d) mod n
            S_CALC_S:    begin mm_a<=tmp1; mm_b<=tmp2; mul_vld<=1; state<=S_CALC_S_MW; end
            S_CALC_S_MW: begin if(mul_fin) begin modn_start<=1; state<=S_CALC_S_RED; end end
            S_CALC_S_RED: state <= S_CALC_S_RW;
            S_CALC_S_RW: begin if(modn_done) begin s_o<=modn_result; state<=S_DONE; end end

            S_DONE: begin done_o <= 1; state <= S_IDLE; end
            default: state <= S_IDLE;
        endcase
    end
end

endmodule
