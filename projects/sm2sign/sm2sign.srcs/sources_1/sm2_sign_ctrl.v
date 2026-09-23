`timescale 1ns / 1ps
// Module: sm2_sign_ctrl
// Description: SM2 digital signature (Sign) controller — HARDWARE version.
//              Uses ljgibbslf's Karatsuba multiplier (mul_ko_256b) and
//              fast mod-p reduction (spd_mod_sub) for all modular arithmetic.
//              Mod-n operations use a sequential 512-cycle divider (mod_n_reduce).
//
//              Algorithm (GB/T 32918.2):
//                1. (x1, y1) = k * G                   [point multiplication]
//                2. z_inv = Z^(p-2) mod p               [Fermat inverse, mod p]
//                3. x1 = XJ * (z_inv)^2 mod p           [Jacobian -> affine]
//                4. r = (e + x1) mod n
//                5. tmp1 = (1+d)^(n-2) mod n            [Fermat inverse, mod n]
//                6. tmp2 = (k - r*d) mod n
//                7. s = tmp1 * tmp2 mod n

module sm2_sign_ctrl (
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

// -----------------------------------------------------------------------
// SM2 curve parameters
// -----------------------------------------------------------------------
localparam [255:0] P256 = 256'hFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF;
localparam [255:0] N256 = 256'hFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123;

// -----------------------------------------------------------------------
// Point multiplication (k*G) — unchanged
// -----------------------------------------------------------------------
// SM2 generator point
localparam [255:0] GX = 256'h32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7;
localparam [255:0] GY = 256'hBC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0;

reg         pm_start;
wire [255:0] pm_xj, pm_yj, pm_zj;
wire         pm_done;

sm2_pm_ctrl U_pm (
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
// Hardware modular multiply sub-system
// -----------------------------------------------------------------------

// Shared 256x256 Karatsuba multiplier
reg  [255:0] mm_a, mm_b;       // operands (must be stable during multiply)
reg          mul_vld;           // 1-cycle pulse to start
wire         mul_fin;           // 1-cycle pulse when done
wire [511:0] mul_product;       // 512-bit result

mul_ko_256b U_mul (
    .clk      (clk),
    .rst_n    (rst_n),
    .mul_vld_i(mul_vld),
    .mul_a_i  (mm_a),
    .mul_b_i  (mm_b),
    .mul_fin_o(mul_fin),
    .mul_r_o  (mul_product)
);

// Fast mod-p reduction (3 cycles)
reg          modp_vld;
wire         modp_fin;
wire [255:0] modp_result;

spd_mod_sub U_modp (
    .clk      (clk),
    .rst_n    (rst_n),
    .mod_vld_i(modp_vld),
    .p512_a   (mul_product),
    .mod_fin_o(modp_fin),
    .p256_b   (modp_result)
);

// Sequential mod-n reduction (512 cycles)
reg          modn_start;
wire         modn_done;
wire [255:0] modn_result;

mod_n_reduce U_modn (
    .clk      (clk),
    .rst_n    (rst_n),
    .start    (modn_start),
    .dividend (mul_product),
    .done     (modn_done),
    .remainder(modn_result)
);

// -----------------------------------------------------------------------
// Modular add/sub — combinational (small, OK for synthesis)
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
// Main FSM
// -----------------------------------------------------------------------
localparam [4:0]
    S_IDLE       = 5'd0,
    S_PM         = 5'd1,   // wait for k*G
    // Fermat inverse loop (shared for mod-p and mod-n)
    S_FE_CMUL    = 5'd2,   // conditional multiply: check bit, start mul
    S_FE_CMUL_MW = 5'd3,   // wait for multiply
    S_FE_CMUL_RD = 5'd4,   // start reduction
    S_FE_CMUL_RW = 5'd5,   // wait for reduction
    S_FE_SQ      = 5'd6,   // squaring: start mul(base, base)
    S_FE_SQ_MW   = 5'd7,   // wait for multiply
    S_FE_SQ_RD   = 5'd8,   // start reduction
    S_FE_SQ_RW   = 5'd9,   // wait for reduction, advance bit
    // Post Fermat-1 (Jacobian -> affine)
    S_ZINV_SQ    = 5'd10,  // start mul: zj_inv^2
    S_ZINV_SQ_MW = 5'd11,
    S_ZINV_SQ_RD = 5'd12,
    S_ZINV_SQ_RW = 5'd13,
    S_X1AFF      = 5'd14,  // start mul: XJ * zj_inv_sq
    S_X1AFF_MW   = 5'd15,
    S_X1AFF_RD   = 5'd16,
    S_X1AFF_RW   = 5'd17,
    S_CALC_R     = 5'd18,  // r = (e + x1) mod n
    // Post Fermat-2 (signature computation)
    S_RD         = 5'd19,  // start mul: r * d mod n
    S_RD_MW      = 5'd20,
    S_RD_RED     = 5'd21,
    S_RD_RW      = 5'd22,
    S_CALC_KRD   = 5'd23,  // tmp2 = (k - r*d) mod n
    S_CALC_S     = 5'd24,  // start mul: tmp1 * tmp2 mod n
    S_CALC_S_MW  = 5'd25,
    S_CALC_S_RED = 5'd26,
    S_CALC_S_RW  = 5'd27,
    S_DONE       = 5'd28;

reg [4:0] state;

// Working registers
reg [255:0] d_latch, e_latch, k_latch;
reg [255:0] xj_latch;
reg [255:0] x1_aff;
reg [255:0] r_tmp;
reg [255:0] tmp1, tmp2;

// Fermat inverse working registers
reg [255:0] fe_result;  // accumulator (starts at 1)
reg [255:0] fe_base;    // base (starts at input value)
reg [255:0] fe_exp;     // exponent being shifted
reg [8:0]   fe_cnt;     // bit counter 0..255 (9-bit to count to 256)
reg         fe_modn;    // 0 = mod p, 1 = mod n
reg [4:0]   fe_ret;     // state to return to after Fermat completes

assign busy_o = (state != S_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= S_IDLE;
        pm_start   <= 1'b0;
        done_o     <= 1'b0;
        r_o        <= 256'd0;
        s_o        <= 256'd0;
        mul_vld    <= 1'b0;
        modp_vld   <= 1'b0;
        modn_start <= 1'b0;
        // Working registers
        d_latch    <= 256'd0;
        e_latch    <= 256'd0;
        k_latch    <= 256'd0;
        xj_latch   <= 256'd0;
        x1_aff     <= 256'd0;
        r_tmp      <= 256'd0;
        tmp1       <= 256'd0;
        tmp2       <= 256'd0;
        // Multiplier operands
        mm_a       <= 256'd0;
        mm_b       <= 256'd0;
        // Fermat inverse registers
        fe_base    <= 256'd0;
        fe_result  <= 256'd0;
        fe_exp     <= 256'd0;
        fe_cnt     <= 9'd0;
        fe_modn    <= 1'b0;
        fe_ret     <= S_IDLE;
    end else begin
        // Defaults: single-cycle pulses
        pm_start   <= 1'b0;
        done_o     <= 1'b0;
        mul_vld    <= 1'b0;
        modp_vld   <= 1'b0;
        modn_start <= 1'b0;

        case (state)
            // ===========================================================
            S_IDLE: begin
                if (start_i) begin
                    d_latch  <= d_i;
                    e_latch  <= e_i;
                    k_latch  <= k_i;
                    pm_start <= 1'b1;
                    state    <= S_PM;
                end
            end

            // ===========================================================
            S_PM: begin
                if (pm_done) begin
                    xj_latch <= pm_xj;
                    // Start Fermat-1: Z^(p-2) mod p
                    fe_base   <= pm_zj;
                    fe_result <= 256'd1;
                    fe_exp    <= P256 - 256'd2;
                    fe_cnt    <= 9'd0;
                    fe_modn   <= 1'b0;       // mod p
                    fe_ret    <= S_ZINV_SQ;   // after Fermat, go to ZINV_SQ
                    state     <= S_FE_CMUL;
                end
            end

            // ===========================================================
            // Fermat inverse loop: right-to-left binary exponentiation
            // Per bit: conditional multiply (result *= base if bit=1),
            //          then square (base *= base).
            // ===========================================================

            // --- Conditional multiply ---
            S_FE_CMUL: begin
                if (fe_exp[0]) begin
                    // bit=1: start result * base
                    mm_a    <= fe_result;
                    mm_b    <= fe_base;
                    mul_vld <= 1'b1;
                    state   <= S_FE_CMUL_MW;
                end else begin
                    // bit=0: skip multiply, go to squaring
                    state <= S_FE_SQ;
                end
            end

            S_FE_CMUL_MW: begin
                if (mul_fin) begin
                    // Multiply done, start reduction
                    if (!fe_modn) begin
                        modp_vld <= 1'b1;
                        state    <= S_FE_CMUL_RD;
                    end else begin
                        modn_start <= 1'b1;
                        state      <= S_FE_CMUL_RD;
                    end
                end
            end

            S_FE_CMUL_RD: begin
                // Wait for reduction
                state <= S_FE_CMUL_RW;
            end

            S_FE_CMUL_RW: begin
                if ((!fe_modn && modp_fin) || (fe_modn && modn_done)) begin
                    fe_result <= fe_modn ? modn_result : modp_result;
                    state     <= S_FE_SQ;
                end
            end

            // --- Squaring ---
            S_FE_SQ: begin
                mm_a    <= fe_base;
                mm_b    <= fe_base;
                mul_vld <= 1'b1;
                state   <= S_FE_SQ_MW;
            end

            S_FE_SQ_MW: begin
                if (mul_fin) begin
                    if (!fe_modn) begin
                        modp_vld <= 1'b1;
                        state    <= S_FE_SQ_RD;
                    end else begin
                        modn_start <= 1'b1;
                        state      <= S_FE_SQ_RD;
                    end
                end
            end

            S_FE_SQ_RD: begin
                state <= S_FE_SQ_RW;
            end

            S_FE_SQ_RW: begin
                if ((!fe_modn && modp_fin) || (fe_modn && modn_done)) begin
                    fe_base <= fe_modn ? modn_result : modp_result;
                    fe_exp  <= {1'b0, fe_exp[255:1]};  // shift right
                    fe_cnt  <= fe_cnt + 9'd1;

                    if (fe_cnt == 9'd255) begin
                        // All 256 bits done, exit Fermat loop
                        state <= fe_ret;
                    end else begin
                        state <= S_FE_CMUL;
                    end
                end
            end

            // ===========================================================
            // Post Fermat-1: Jacobian -> Affine conversion
            // ===========================================================

            // zj_inv_sq = fe_result^2 mod p
            S_ZINV_SQ: begin
                mm_a    <= fe_result;
                mm_b    <= fe_result;
                mul_vld <= 1'b1;
                state   <= S_ZINV_SQ_MW;
            end
            S_ZINV_SQ_MW: begin
                if (mul_fin) begin
                    modp_vld <= 1'b1;
                    state    <= S_ZINV_SQ_RD;
                end
            end
            S_ZINV_SQ_RD: state <= S_ZINV_SQ_RW;
            S_ZINV_SQ_RW: begin
                if (modp_fin) begin
                    tmp1  <= modp_result;  // zj_inv_sq
                    state <= S_X1AFF;
                end
            end

            // x1 = XJ * zj_inv_sq mod p
            S_X1AFF: begin
                mm_a    <= xj_latch;
                mm_b    <= tmp1;
                mul_vld <= 1'b1;
                state   <= S_X1AFF_MW;
            end
            S_X1AFF_MW: begin
                if (mul_fin) begin
                    modp_vld <= 1'b1;
                    state    <= S_X1AFF_RD;
                end
            end
            S_X1AFF_RD: state <= S_X1AFF_RW;
            S_X1AFF_RW: begin
                if (modp_fin) begin
                    x1_aff <= modp_result;
                    state  <= S_CALC_R;
                end
            end

            // ===========================================================
            // r = (e + x1) mod n, then start Fermat-2
            // ===========================================================
            S_CALC_R: begin
                r_tmp <= mod_add(e_latch, x1_aff, N256);
                // Start Fermat-2: (1+d)^(n-2) mod n
                fe_base   <= mod_add(256'd1, d_latch, N256);
                fe_result <= 256'd1;
                fe_exp    <= N256 - 256'd2;
                fe_cnt    <= 9'd0;
                fe_modn   <= 1'b1;       // mod n
                fe_ret    <= S_RD;        // after Fermat, go to RD
                state     <= S_FE_CMUL;
            end

            // ===========================================================
            // Post Fermat-2: Signature computation
            // ===========================================================

            // tmp2 = r * d mod n
            S_RD: begin
                tmp1    <= fe_result;     // (1+d)^{-1} mod n
                mm_a    <= r_tmp;
                mm_b    <= d_latch;
                mul_vld <= 1'b1;
                r_o     <= r_tmp;         // latch r output
                state   <= S_RD_MW;
            end
            S_RD_MW: begin
                if (mul_fin) begin
                    modn_start <= 1'b1;
                    state      <= S_RD_RED;
                end
            end
            S_RD_RED: state <= S_RD_RW;
            S_RD_RW: begin
                if (modn_done) begin
                    tmp2  <= modn_result;  // r*d mod n
                    state <= S_CALC_KRD;
                end
            end

            // tmp2 = (k - r*d) mod n
            S_CALC_KRD: begin
                tmp2  <= mod_sub(k_latch, tmp2, N256);
                state <= S_CALC_S;
            end

            // s = tmp1 * tmp2 mod n
            S_CALC_S: begin
                mm_a    <= tmp1;
                mm_b    <= tmp2;
                mul_vld <= 1'b1;
                state   <= S_CALC_S_MW;
            end
            S_CALC_S_MW: begin
                if (mul_fin) begin
                    modn_start <= 1'b1;
                    state      <= S_CALC_S_RED;
                end
            end
            S_CALC_S_RED: state <= S_CALC_S_RW;
            S_CALC_S_RW: begin
                if (modn_done) begin
                    s_o   <= modn_result;
                    state <= S_DONE;
                end
            end

            // ===========================================================
            S_DONE: begin
                done_o <= 1'b1;
                state  <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
