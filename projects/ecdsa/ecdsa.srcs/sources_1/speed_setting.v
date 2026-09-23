`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:46:16 03/27/2019 
// Design Name: 
// Module Name:    speed_setting 
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
//
//////////////////////////////////////////////////////////////////////////////////
module speed_setting(
			input clk,
			input rst_n,
			input bps_start,
			output clk_bps
    );

// `define CLK_PERIORD     250  // Clock period in ns, 4MHz
`define CLK_PERIORD     20   // Clock period in ns, 50MHz (temporary bypass PLL, consistent with recv_data)
`define BPS_SET         1152 // Baud rate / 100, 115200 bps

`define BPS_PARA        (10_000_000/`CLK_PERIORD/`BPS_SET)
`define BPS_PARA_2      (`BPS_PARA/2)

reg[12:0] cnt;       // Baud rate divider counter
reg clk_bps_r;       // Baud rate clock register
reg[2:0] uart_ctrl;  // UART baud rate select register

always @ (posedge clk or negedge rst_n)
        if(!rst_n) cnt<=13'd0;
        else if((cnt==`BPS_PARA) || !bps_start) cnt<=13'd0; // Reset counter when done or idle
        else cnt<=cnt+1'b1;                                  // Increment baud rate counter

always @ (posedge clk or negedge rst_n)
        if(!rst_n) clk_bps_r<=1'b0;
        else if(cnt==`BPS_PARA_2) clk_bps_r<=1'b1;          // Pulse at midpoint of bit period
        else clk_bps_r<=1'b0;

assign clk_bps = clk_bps_r;

endmodule













