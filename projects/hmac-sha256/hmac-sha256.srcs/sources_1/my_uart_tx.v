`timescale 1ns / 1ps
`default_nettype wire
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:05:44 03/28/2019 
// Design Name: 
// Module Name:    my_uart_tx 
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
module my_uart_tx(
			input clk,
			input rst_n,
			input[7:0] data,
			input wr_en,
			output uart_tx,
			output tx_busy,
			input clk_bps,
			output bps_start
    );

reg[7:0]tx_data;
reg bps_start_r;
reg tx_en;
reg[3:0]num;

always @ (posedge clk or negedge rst_n)
	if(!rst_n)begin
		bps_start_r <= 1'b0;
		tx_en <= 1'b0;
		tx_data <= 8'd0;
	end
	
	else if(wr_en)begin
		bps_start_r <= 1'b1;
		tx_data <= data;
		tx_en <= 1'b1;
	end
	
	else if(num==4'd10)begin
		bps_start_r <= 1'b0;
		tx_en <= 1'b0;
	end
	
assign bps_start = bps_start_r;

reg uart_tx_r;
always @ (posedge clk or negedge rst_n)
	if(!rst_n)begin
		num <=4'd0;
		uart_tx_r <= 1'b1;
	end
	
	else if(tx_en)begin
		if(clk_bps)begin
			num <= num+1'b1;
			case(num)
			4'd0:uart_tx_r <= 1'b0;
			4'd1:uart_tx_r <= tx_data[0];
			4'd2:uart_tx_r <= tx_data[1];
			4'd3:uart_tx_r <= tx_data[2];
			4'd4:uart_tx_r <= tx_data[3];
			4'd5:uart_tx_r <= tx_data[4];
			4'd6:uart_tx_r <= tx_data[5];
			4'd7:uart_tx_r <= tx_data[6];
			4'd8:uart_tx_r <= tx_data[7];
			4'd9:uart_tx_r <= 1'b1;
			default:uart_tx_r <= 1'b1;
			endcase
		end
		else if(num==4'd10)num <= 4'd0;
		
	end
assign uart_tx = uart_tx_r;	
assign  tx_busy = tx_en;
endmodule










