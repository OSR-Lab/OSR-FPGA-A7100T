`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:         SHU
// Engineer:        lf
// 
// Create Date:    21:24:31 04/01/2020 
// Design Name: 
// Module Name:    mul_ko_256b 
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
// builds a 256b multiplier from 128b multipliers using Karatsuba-Ofman (k =2) divide and conquer
// the 128b multipliers used here are themselves divide-and-conquer, with a 4-cycle latency and registered outputs
// parallel version using three multipliers
// 
//////////////////////////////////////////////////////////////////////////////////
module mul_ko_256b(
    input           clk,
    input           rst_n,

    input           mul_vld_i,//result valid signal

    input [255:0]   mul_a_i,
    input [255:0]   mul_b_i,

    output          mul_fin_o,
    output  [511:0] mul_r_o
);

//split the inputs {A,B}x{C,D} and pre-process them
wire [127:0]        mul_A;
wire [127:0]        mul_B;
wire [127:0]        mul_C;
wire [127:0]        mul_D;
reg  [128:0]        mul_CpD;
reg  [128:0]        mul_ApB;
reg [129:0]         mul_ApBxCpD_adj; //correction when a 129-bit operand uses the 128-bit multiplier

//128-bit unsigned multiplier IP
wire [127: 0]       mul_128a_a;
wire [127: 0]       mul_128a_b;
wire [255 : 0]      mul_128a_p;

wire [127: 0]       mul_128b_a;
wire [127: 0]       mul_128b_b;
wire [255 : 0]      mul_128b_p;

wire [127: 0]       mul_128c_a;
wire [127: 0]       mul_128c_b;
wire [255 : 0]      mul_128c_p;

//take the rising edge of the valid signal and generate the done signal
reg                 mul_vld_r1;
wire                mul_vld_redge;
reg                 mul_fin;

//handle the cycle flag
wire                mul_cyc_0;
reg                 mul_cyc_1,mul_cyc_2,mul_cyc_3,mul_cyc_4;

//intermediate result registers
reg  [383:0]        mul_r_mid;   
reg  [383:0]        mul_r_mid_1;   

//split the inputs {A,B}x{C,D}
assign              {mul_A,mul_B}   =   mul_a_i;
assign              {mul_C,mul_D}   =   mul_b_i;

//cut the adder out of the path
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_CpD     <=   129'd0;
        mul_ApB     <=   129'd0;
    end else if(mul_cyc_0)begin
        mul_CpD     <=   mul_D + mul_C; 
        mul_ApB     <=   mul_B + mul_A;
    end
end

//correct the multiplication
//if mul_CpD[0] && ~mul_ApB[0], then mul_ApB was omitted; the same applies in reverse
//if mul_CpD[0] &&  mul_ApB[0], then mul_ApB mul_CpD was omitted and an extra 1 was added, so correct it
// assign              mul_ApBxCpD_adj =   mul_cyc_4 ? (
//                                         ( mul_CpD[0] && ~mul_ApB[0])? mul_ApB :
//                                         (~mul_CpD[0] &&  mul_ApB[0])? mul_CpD :
//                                         ( mul_CpD[0] &&  mul_ApB[0])? mul_ApB + mul_CpD - 1'b1:
//                                         65'd0):
//                                         65'd0
//                                     ;

//accumulate mul_ApBxCpD_adj in a register to shorten the critical path
always @(posedge clk or negedge rst_n) begin
    if(~rst_n | mul_cyc_0) begin
        mul_ApBxCpD_adj              <= 129'b0;
    end else if(mul_cyc_1 && mul_CpD[0])begin
        mul_ApBxCpD_adj              <= mul_ApBxCpD_adj + mul_ApB;
    end else if(mul_cyc_2 && mul_ApB[0])begin
        mul_ApBxCpD_adj              <= mul_ApBxCpD_adj + mul_CpD;
    end else if(mul_cyc_3 && mul_ApB[0] && mul_CpD[0])begin
        mul_ApBxCpD_adj              <= mul_ApBxCpD_adj - 1'b1;
    end
end


//assign the multiplier inputs: multiplier A gets AxC, B gets BxD, C gets (A+B)x(C+D)
assign              mul_128a_a  =   mul_A;
assign              mul_128a_b  =   mul_C;
assign              mul_128b_a  =   mul_B;
assign              mul_128b_b  =   mul_D;
assign              mul_128c_a  =   mul_CpD[128-:128];//a 129-bit operand using the 128-bit multiplier
assign              mul_128c_b  =   mul_ApB[128-:128];//a 129-bit operand using the 128-bit multiplier

//take the rising edge of the valid signal and generate the done signal
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_vld_r1              <= 1'b0;
    end else begin
        mul_vld_r1              <= mul_vld_i;
    end
end

assign              mul_vld_redge   =   mul_vld_i && ~mul_vld_r1;
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_fin              <= 1'b0;
    end else begin
        mul_fin              <= mul_cyc_4;
    end
end

//handle the cycle flag
assign              mul_cyc_0       =   mul_vld_redge;
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        {mul_cyc_1,mul_cyc_2,mul_cyc_3,mul_cyc_4}<= 4'b0;
    end else begin
        {mul_cyc_1,mul_cyc_2,mul_cyc_3,mul_cyc_4}<=
        {mul_cyc_0,mul_cyc_1,mul_cyc_2,mul_cyc_3};
    end
end

//intermediate result computed in mul_cyc_3; the 128-bit left shift is kept here to reduce the operand width
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_r_mid              <= 384'b0;
    end else if(mul_cyc_3)begin//{AC,BD}
        mul_r_mid              <= {mul_128a_p,mul_128b_p[255-:128]} - {128'd0,mul_128a_p} - {128'd0,mul_128b_p}; 
    end
end

//result computed in mul_cyc_4; the 128-bit left shift is kept here to reduce the operand width
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_r_mid_1              <= 384'b0;
    end else if(mul_cyc_4)begin //mul_64r_ApBxCpD
        mul_r_mid_1              <= {mul_128c_p,2'b00} + mul_r_mid + {mul_ApBxCpD_adj};//mul_64r_ApBxCpD needs correction
    end
end

//128-bit divide-and-conquer multiplier, 4-cycle latency, registered output
mul_ko_128b U_mul_128_a (
    .clk(clk), 
    .rst_n(rst_n), 
    .mul_vld_i(mul_vld_i), 
    .mul_a_i(mul_128a_a), 
    .mul_b_i(mul_128a_b), 
    .mul_r_o(mul_128a_p),
    .mul_fin_o()
    );

mul_ko_128b U_mul_128_b (
    .clk(clk), 
    .rst_n(rst_n), 
    .mul_vld_i(mul_vld_i), 
    .mul_a_i(mul_128b_a), 
    .mul_b_i(mul_128b_b), 
    .mul_r_o(mul_128b_p),
    .mul_fin_o()
    );

mul_ko_128b U_mul_128_c (
    .clk(clk), 
    .rst_n(rst_n), 
    .mul_vld_i(mul_vld_r1), //starts one cycle after the addition finishes
    .mul_a_i(mul_128c_a), 
    .mul_b_i(mul_128c_b), 
    .mul_r_o(mul_128c_p),
    .mul_fin_o()
    );

//output control
assign              mul_fin_o       =       mul_fin;
//the low 128 bits are restored here
assign              mul_r_o         =       {mul_r_mid_1,mul_128b_p[127:0]};

endmodule
