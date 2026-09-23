`timescale 1ns / 1ps
`default_nettype wire
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    10:54:32 08/16/2019 
// Design Name: 
// Module Name:    uart 
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
module uart(
		 input wire [7:0] din,
		 input wire wr_en,
		 input wire clk_50m,
		 output wire tx,
		 output wire tx_busy,
		 input wire rx,
		 output wire rx_busy,
		 input wire rst,
		 output wire [7:0] dout
 );




wire bps_start1,bps_start2;
wire clk_bps1,clk_bps2;

wire[7:0] rx_data;
wire rx_int;
wire wr_en_neg;


speed_setting speed_rx(
						.clk(clk_50m),
						.rst_n(rst),
						.bps_start(bps_start1),
						.clk_bps(clk_bps1)
						);

	
my_uart_rx	my_uart_rx_r(
						.clk(clk_50m),
						.rst_n(rst),
						.uart_rx(rx),
						.rx_data(dout),
						.rx_int(rx_busy),
						.clk_bps(clk_bps1),
						.bps_start(bps_start1));


speed_setting speed_tx(
						.clk(clk_50m),
						.rst_n(rst),
						.bps_start(bps_start2),
						.clk_bps(clk_bps2)
						);

my_uart_tx my_uart_tx_r(
						.clk(clk_50m),
						.rst_n(rst),
						.data(din),
						.wr_en(wr_en),
						.tx_busy(tx_busy),
						.uart_tx(tx),
						.clk_bps(clk_bps2),
						.bps_start(bps_start2));

endmodule

