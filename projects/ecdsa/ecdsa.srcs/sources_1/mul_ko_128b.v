`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:         SHU
// Engineer:        lf
// 
// Create Date:    09:49:50 04/01/2020 
// Design Name: 
// Module Name:    mul_ko_128b 
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
//builds a 128b multiplier from 64b multipliers using Karatsuba-Ofman (k =2) divide and conquer
//includes two 256b adders, 3 multiplications and 4 add/subtract operations
//uses two 128-bit intermediate registers plus a 256-bit result register
//compute {A,B}x{C,D}
//cyc0:   M=B x D    P=B+D   Q=A+C
//cyc1:   N=A x C    S = {M,N} - (N << 64)
//cyc2:   S = S - (M << 64)  T = P X Q  S = S + T
//critical path: multiply + add
//latency: 3clk + 1clk (output register)
//////////////////////////////////////////////////////////////////////////////////
module mul_ko_128b(
    input           clk,
    input           rst_n,

    input           mul_vld_i,//result valid signal

    input [127:0]   mul_a_i,
    input [127:0]   mul_b_i,

    output          mul_fin_o,
    output [255:0]  mul_r_o
);

//local parameters
`define  USE_192B_ADD_SUB  //uses a 192b adder/subtractor instead of a 256b one

//split the inputs {A,B}x{C,D} and pre-process them
wire [63:0]         mul_A;
wire [63:0]         mul_B;
wire [63:0]         mul_C;
wire [63:0]         mul_D;
reg  [64:0]         mul_CpD;
reg  [64:0]         mul_ApB;
reg  [65:0]         mul_ApBxCpD_adj; //correction when a 65-bit operand uses the 64-bit multiplier

//64-bit unsigned multiplier IP
wire [63 : 0]       mul_64a_a;
wire [63 : 0]       mul_64a_b;
wire [127 : 0]      mul_64a_p;

//multiplier output registers
reg  [127:0]        mul_64r_BxD;
reg  [127:0]        mul_64r_AxC;
reg  [127:0]        mul_64r_ApBxCpD;

//take the rising edge of the valid signal and generate the done signal
reg                 mul_vld_r1;
reg                 mul_vld_r2;
reg                 mul_vld_r3;
wire                mul_vld_redge;
reg                 mul_fin;

//handle the cycle flag
wire                mul_cyc_0;
wire                mul_cyc_1;
wire                mul_cyc_2;

//intermediate result registers
`ifdef USE_192B_ADD_SUB
reg  [191:0]       mul_r_mid;      
reg  [191:0]       mul_r_mid_1;    
`else
reg  [255:0]       mul_r_mid;      
reg  [255:0]       mul_r_mid_1;   
`endif  

//reuse a single 64b adder
wire [63:0]         add_64b_a;
wire [63:0]         add_64b_b;
wire [64:0]         add_64b_r;

//split the inputs {A,B}x{C,D}
assign              {mul_A,mul_B}   =   mul_a_i;
assign              {mul_C,mul_D}   =   mul_b_i;

//reuse a single 64b adder
assign              add_64b_r = add_64b_a + add_64b_b;
assign              add_64b_a = mul_cyc_0 ? mul_A:mul_C;
assign              add_64b_b = mul_cyc_0 ? mul_B:mul_D;

//cut the adder out of the path
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_CpD     <=   65'd0;
        mul_ApB     <=   65'd0;
    end else if(mul_cyc_0)begin //perform the additions in parallel
        mul_ApB     <=   mul_A + mul_B; 
        mul_CpD     <=   mul_C + mul_D; 
    // end else if(mul_cyc_1)begin
    end
end

//multiplier input control
assign              mul_64a_a   =   mul_cyc_0 ? mul_B:
                                    mul_cyc_1 ? mul_A:
                                    mul_cyc_2 ? mul_CpD[64-:64]://taking the high bits directly would lose precision, so compensation is needed
                                    64'd0
                                    ;
assign              mul_64a_b   =   mul_cyc_0 ? mul_D:
                                    mul_cyc_1 ? mul_C:
                                    mul_cyc_2 ? mul_ApB[64-:64]:
                                    64'd0
                                    ;

//correct the multiplication
//if mul_CpD[0] && ~mul_ApB[0], then mul_ApB was omitted; the same applies in reverse
//if mul_CpD[0] &&  mul_ApB[0], then mul_ApB mul_CpD was omitted and an extra 1 was added, so correct it
// assign              mul_ApBxCpD_adj =   mul_cyc_2 ? (
//                                         ( mul_CpD[0] && ~mul_ApB[0])? mul_ApB :
//                                         (~mul_CpD[0] &&  mul_ApB[0])? mul_CpD :
//                                         ( mul_CpD[0] &&  mul_ApB[0])? mul_ApB + mul_CpD - 1'b1:
//                                         65'd0):
//                                         65'd0
//                                     ;

//to move the correction logic off the critical path, it is implemented as flip-flops
always @(posedge clk or negedge rst_n) begin
    if(~rst_n | mul_cyc_0) begin
        mul_ApBxCpD_adj              <= 65'b0;
    end else if(mul_cyc_1)begin
        mul_ApBxCpD_adj              <=( mul_CpD[0] && ~mul_ApB[0])? mul_ApB :
                                    (~mul_CpD[0] &&  mul_ApB[0])? mul_CpD :
                                    ( mul_CpD[0] &&  mul_ApB[0])? mul_ApB + mul_CpD - 1'b1:
                                    65'd0;
    end
end

//multiplier output registers
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_64r_BxD        <=  128'd0;
        mul_64r_AxC        <=  128'd0; //not actually used
        mul_64r_ApBxCpD    <=  128'd0; //not actually used
    end else begin
        mul_64r_BxD        <=  mul_cyc_0 ? mul_64a_p : mul_64r_BxD    ;
        mul_64r_AxC        <=  mul_cyc_1 ? mul_64a_p : mul_64r_AxC    ;
        mul_64r_ApBxCpD    <=  mul_cyc_2 ? mul_64a_p : mul_64r_ApBxCpD;
    end
end

//take the rising edge of the valid signal and generate the done signal
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_vld_r1              <= 1'b0;
        mul_vld_r2              <= 1'b0;
        mul_vld_r3              <= 1'b0;
    end else begin
        mul_vld_r1              <= mul_vld_i;
        mul_vld_r2              <= mul_vld_r1;
        mul_vld_r3              <= mul_vld_r2;
    end
end

assign              mul_vld_redge   =   mul_vld_i && ~mul_vld_r1;
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_fin              <= 1'b0;
    end else begin
        mul_fin              <= mul_cyc_2;
    end
end
//handle the cycle flag
assign              mul_cyc_0       =   mul_vld_i && ~mul_vld_r1;
assign              mul_cyc_1       =   mul_vld_r1 && ~mul_vld_r2;
assign              mul_cyc_2       =   mul_vld_r2 && ~mul_vld_r3;


//intermediate result computed in mul_cyc_1
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_r_mid              <= 256'b0;
    end else if(mul_cyc_1)begin//mul_64a_p is mul_64r_AxC here
        `ifdef USE_192B_ADD_SUB
        mul_r_mid              <= {mul_64a_p,mul_64r_BxD[127-:64]} - mul_64a_p - mul_64r_BxD; //-{mul_64r_AxC,64'd0} -{mul_64r_BxD,64'd0} 
        `else
        mul_r_mid              <= {mul_64a_p,mul_64r_BxD} - {64'd0,mul_64a_p,64'd0} - {64'd0,mul_64r_BxD,64'd0}; //-{mul_64r_AxC,64'd0} -{mul_64r_BxD,64'd0} 
        `endif
    end
end

//result computed in mul_cyc_2
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        mul_r_mid_1              <= 256'b0;
    end else if(mul_cyc_2)begin //mul_64a_p is mul_64r_ApBxCpD here
        `ifdef USE_192B_ADD_SUB
        mul_r_mid_1              <= {mul_64a_p,2'b00} + mul_r_mid + mul_ApBxCpD_adj;//mul_64r_ApBxCpD needs correction        `endif
        `else
        mul_r_mid_1              <= {mul_64a_p,2'b00,64'h0} + mul_r_mid + {mul_ApBxCpD_adj,64'h0};//mul_64r_ApBxCpD needs correction
        `endif
    end
end

//64-bit unsigned multiplier IP
mul_64b_wrapper U_mul_64_a (
  .a(mul_64a_a), // input [63 : 0] a
  .b(mul_64a_b), // input [63 : 0] b
  .p(mul_64a_p) //  output [127 : 0] p
);

//output control
assign              mul_fin_o       =       mul_fin;

`ifdef USE_192B_ADD_SUB
assign              mul_r_o         =       {mul_r_mid_1,mul_64r_BxD[63:0]};
`else
assign              mul_r_o         =       mul_r_mid_1;
`endif

endmodule
