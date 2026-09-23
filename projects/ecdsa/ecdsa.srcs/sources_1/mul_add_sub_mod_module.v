`timescale 1ns / 1ps
// Module: mul_add_sub_mod_module
// Description: Modular multiply, add, and subtract for NIST P-256.
//              MUL uses mul_ko_256b + spd_mod_sub (NIST P-256 fast reduction).
//              ADD/SUB are combinational with conditional ±p correction.
//
//              op_sel_i:
//                2'b00 : modular multiply (a * b mod p)
//                2'b01 : modular add      (a + b mod p)
//                2'b10 : modular subtract (a - b mod p)

module mul_add_sub_mod_module(
    input           clk,
    input           rst_n,

    input           op_vld_i,
    input [1:0]     op_sel_i,
    input [255:0]   op_mod_num_i,   // modulus (used for ADD/SUB)

    input [255:0]   op_a_i,
    input [255:0]   op_b_i,

    output          op_done_o,
    output [255:0]  op_rslt_o
);

localparam OP_MUL = 2'b00;
localparam OP_ADD = 2'b01;
localparam OP_SUB = 2'b10;

wire op_is_mul = (op_sel_i == OP_MUL);
wire op_is_add = (op_sel_i == OP_ADD);
wire op_is_sub = (op_sel_i == OP_SUB);

// -----------------------------------------------------------------------
// MUL path: mul_ko_256b -> spd_mod_sub (P-256 fast reduction)
// -----------------------------------------------------------------------
wire [511:0] mul_product;
wire         mul_fin;
wire         mul_vld = op_is_mul && op_vld_i;

mul_ko_256b U_mul (
    .clk(clk), .rst_n(rst_n),
    .mul_vld_i(mul_vld),
    .mul_a_i(op_a_i), .mul_b_i(op_b_i),
    .mul_fin_o(mul_fin), .mul_r_o(mul_product)
);

wire         modp_fin;
wire [255:0] modp_result;

spd_mod_sub U_modp (
    .clk(clk), .rst_n(rst_n),
    .mod_vld_i(mul_fin),
    .p512_a(mul_product),
    .mod_fin_o(modp_fin), .p256_b(modp_result)
);

// -----------------------------------------------------------------------
// ADD/SUB path: combinational with conditional ±p
// -----------------------------------------------------------------------
wire add_sub_vld = (op_is_add || op_is_sub) && op_vld_i;

// Reason: ADD: result = (a + b), if >= p then subtract p
//         SUB: result = (a - b), if borrow then add p
wire [256:0] add_result = {1'b0, op_a_i} + {1'b0, op_b_i};
wire [256:0] add_mod    = add_result - {1'b0, op_mod_num_i};
wire         add_need_sub = ~add_mod[256];  // add_result >= p

wire [256:0] sub_result = {1'b0, op_a_i} - {1'b0, op_b_i};
wire [256:0] sub_mod    = sub_result + {1'b0, op_mod_num_i};
wire         sub_borrow = sub_result[256];   // a < b, need + p

wire [255:0] add_sub_out = op_is_add ?
    (add_need_sub ? add_mod[255:0] : add_result[255:0]) :
    (sub_borrow   ? sub_mod[255:0] : sub_result[255:0]);

// -----------------------------------------------------------------------
// Output mux
// -----------------------------------------------------------------------
// Reason: ADD/SUB done immediately (1 cycle for edge detection compatibility)
// MUL done after multiply + reduction pipeline
reg add_sub_vld_r1;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) add_sub_vld_r1 <= 0;
    else        add_sub_vld_r1 <= add_sub_vld;
end
wire add_sub_done = add_sub_vld && ~add_sub_vld_r1;  // rising edge

assign op_done_o = op_is_mul ? modp_fin : add_sub_done;
assign op_rslt_o = op_is_mul ? modp_result : add_sub_out;

endmodule
