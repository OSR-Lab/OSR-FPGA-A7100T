`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:         SHU
// Engineer:        lf
// 
// Create Date:    20:41:49 04/13/2020 
// Design Name: 
// Module Name:    spd_mod_sub_stgb  (stage B; stage B is the module currently in use, replacing spd_mod_sub (stage A))
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//  uses fast modular reduction b = a mod p256, 0<a<p^2
//  takes SPD_MOD_PIPE_STAGE cycles
//  output-side modular reduction logic for the case when the result valid signal is inactive
//////////////////////////////////////////////////////////////////////////////////
module spd_mod_sub_stgb(
    input           clk,
    input           rst_n,

    input           mod_vld_i,
    input [1:0]     op_sel_i,
    input [255:0]   op_mod_num_i,

    input [511:0]   p512_a,
    
    output[255:0]   op_add_sub_res,

    output          mod_fin_o,
    output reg [255:0]   p256_b
);

`define     SPD_MOD_PIPE_STAGE 3

localparam      OP_MUL = 2'b00;
localparam      OP_ADD = 2'b01;
localparam      OP_SUB = 2'b10;

//modular add/subtract logic
wire [255:0]    op_a;
wire [255:0]    op_b;

wire [255:0]    mod_num_p_cmp; //two's complement of -p during modular subtraction
wire [255:0]    op_b_cmp;//two's complement of -b during modular subtraction
wire            op_is_add;
wire            op_is_sub;

//A represented as sixteen 32-bit words
reg  [31:0]     m [15:0];

//14 intermediate variables
wire [255:0]    s [14:0];

//290-bit intermediate variable
wire [289:0]    a_mid_290;
reg  [289:0]    a_mid_290_tmp;
reg  [289:0]    a_mid_290_tmp_1;

//nine intermediate variables of a_mid_290
reg  [31:0]     mm [8:0]; 

//34-bit variable used to accumulate s11-s14
reg  [33:0]     s_tmp_11_14;

//intermediate output register
wire [255:0]    t1;
wire [255:0]    t2;
wire [255:0]    t3;
wire [256:0]    out_m;
wire [256:0]    out_m_mod;
wire            out_m_c;//output is >= p, so p must be subtracted
wire            out_m_mod_c;//output is >= p, so p must be subtracted

//take the rising edge of the valid signal and generate the done signal
reg                 mod_vld_r1;
wire                mod_vld_redge;

//handle the cycle flag
wire                mul_cyc_0;
reg                 mul_cyc_1,mul_cyc_2,mul_cyc_3;

//modulus
wire [256:0]        op_mod_num;
wire [256:0]        op_mod_num_cmp;

//constant p256
wire [255:0]    P256 = {
    8'hFF, 8'hFF, 8'hFF, 8'hFE, 8'hFF, 8'hFF, 8'hFF, 8'hFF, /* p */
    8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF,
    8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'h00, 8'h00, 8'h00, 8'h00,
    8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF 
    } ;
//wire [255:0]    P256;
//assign            P256 = op_mod_num_i;

integer i;

//modular add/subtract logic
assign          {op_a,op_b}     =   p512_a;

//two's complement of -p during modular subtraction
assign          mod_num_p_cmp   =   op_is_add ? op_mod_num_i : ( ~op_mod_num_i ) + 1'b1; 
//two's complement of -b during modular subtraction
assign          op_b_cmp        =   op_is_add ? op_b : ( ~op_b ) + 1'b1; 

assign          op_is_add       =   op_sel_i == OP_ADD;
assign          op_is_sub       =   op_sel_i == OP_SUB;
assign          op_is_mul       =   op_sel_i == OP_MUL;

//take the rising edge of the valid signal and generate the done signal
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mod_vld_r1              <= 1'b0;
    end else begin
        mod_vld_r1              <= mod_vld_i;
    end
end

assign              mod_vld_redge   =   mod_vld_i && ~mod_vld_r1;
//handle the cycle flag
assign              mul_cyc_0       =   mod_vld_redge;
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        {mul_cyc_1,mul_cyc_2,mul_cyc_3}   <= 3'b0;
    end else if(op_is_mul)begin
        {mul_cyc_1,mul_cyc_2,mul_cyc_3}   <= {mul_cyc_0,mul_cyc_1,mul_cyc_2};
    end
end


always@(*)begin
    for (i = 0; i<=15 ; i = i + 1 ) begin
        m[i] = p512_a[32*(i + 1) - 1 -:32];
    end
end

always@(*)begin
    for (i = 0; i<=8 ; i = i + 1 ) begin
        mm[i] = a_mid_290[32*(i + 1) - 1 -:32];
    end
end

assign      s[0] =    {32'h0	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0	, 32'h0	,32'h0};
assign      s[1] =    {m[7] 	,m[6]	,m[5]	,m[4]	,m[3]	,m[2]	,m[1]	,m[0]};
assign      s[2] =    {m[15]	,m[14]	,m[13]	,m[12]	,m[11]	,32'h0	,m[9]	,m[8]};
assign      s[3] =    {m[14]	,32'h0	,m[15]	,m[14]	,m[13]	,32'h0	,m[14]	,m[13]};
assign      s[4] =    {m[13]	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0	,m[15]	,m[14]};
assign      s[5] =    {m[12]	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0	,m[15]};
assign      s[6] =    {m[11]	,m[11]	,m[10]	,m[15]	,m[14]	,32'h0	,m[13]	,m[12]};
assign      s[7] =    {m[10]	,m[15]	,m[14]	,m[13]	,m[12]	,32'h0	,m[11]	,m[10]};
assign      s[8] =    {m[9] 	,32'h0	,32'h0	,m[9]	,m[8]	,32'h0	,m[10]	,m[9]};
assign      s[9] =    {m[8] 	,32'h0	,32'h0	,32'h0	,m[15]	,32'h0	,m[12]	,m[11]};
assign      s[10] =   {m[15]	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0	,32'h0};
assign      s[11] =   {32'h0	,32'h0	,32'h0	,32'h0	,32'h0	, m[14]	, 32'h0	,32'h0};
assign      s[12] =   {32'h0	,32'h0	,32'h0	,32'h0	,32'h0	, m[13]	, 32'h0	,32'h0};
assign      s[13] =   {32'h0	,32'h0	,32'h0	,32'h0	,32'h0	, m[9]	, 32'h0	,32'h0};
assign      s[14] =   {32'h0	,32'h0	,32'h0	,32'h0	,32'h0	, m[8]	, 32'h0	,32'h0};
// assign      a_mid_290 = s[1]+s[2]+2*(s[3]+s[4]+s[5]+s[10])+s[6]+s[7]+s[8]+s[9]-(s[11]+s[12]+s[13]+s[14]);
assign      a_mid_290 = a_mid_290_tmp_1;

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        s_tmp_11_14                <= 34'd0;
        a_mid_290_tmp              <= 290'b0;
        a_mid_290_tmp_1            <= 290'b0;
    end else if(mul_cyc_0)begin
        s_tmp_11_14                <= m[14]+m[13]+m[9]+m[8];
        a_mid_290_tmp              <= s[1]+s[2]+2*(s[3]+s[4]+s[5]+s[10])+s[6]+s[7] ;
    end else if(mul_cyc_1)begin
        a_mid_290_tmp_1            <= a_mid_290_tmp-{s_tmp_11_14,64'h0}+s[8]+s[9];
    end
end

//the modular reduction adder/subtractor is selected and reused for modular addition and subtraction
assign      t1  =   op_is_mul ? {mm[7],mm[6],mm[5],mm[4],mm[3],mm[2],mm[1],mm[0]}
                    :   op_a;
assign      t2  =   op_is_mul ? {mm[8], 32'h0,32'h0,32'h0,mm[8],32'h0,32'h0,mm[8]}
                    :   op_b_cmp;
assign      t3  =   op_is_mul ? {32'h0,32'h0,32'h0,32'h0,32'h0, mm[8], 32'h0,32'h0}
                    :   256'd0;
assign      op_mod_num = (op_is_mul || op_is_add) ? op_mod_num_cmp : op_mod_num_i;
assign      op_mod_num_cmp  =   {1'b1,{~op_mod_num_i + 1'b1}};
//output
assign          out_m           = t1 + t2 - t3;         //stage 1 operands: add/subtract
assign          out_m_mod       = out_m + op_mod_num; //subtract P during modular reduction  //stage 2: add/subtract the result and the modulus
// assign          out_m_mod       = out_m - op_mod_num_i;   //stage 2: add/subtract the result and the modulus

assign          out_m_c         =   out_m[256];    //stage 1 add/subtract carry
assign          out_m_mod_c     =   out_m_mod[256];//stage 2 modular add/subtract carry

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        p256_b              <= 256'b0;
    end else if(mul_cyc_2)begin
        p256_b <= out_m_mod_c ? out_m[255:0] : out_m_mod[255:0];
    end
end

//output control
assign              mod_fin_o       =       op_is_sub || op_is_add ? mul_cyc_0 : mul_cyc_3;

//reuse the output of the modular add/subtract logic
assign              op_add_sub_res  =       ( (out_m_mod_c && op_is_add) || (out_m_c && op_is_sub))?  //addition: stage 2 subtraction carry (negative result); subtraction: stage 1 addition carry (positive result), then take the stage 1 result
                                            out_m[255:0]
                                        :   out_m_mod[255:0]
                                        ;
endmodule
