`timescale 1ns / 1ps




module my_uart_rx(
		input clk,
		input rst_n,
		input uart_rx,
		output[7:0] rx_data,
		output reg rx_int,
		input clk_bps,
		output bps_start
    );

reg uart_rx0,uart_rx1,uart_rx2,uart_rx3;
wire neg_uart_rx;

always @ (posedge clk or negedge rst_n)
	if(!rst_n)begin
		uart_rx0 <= 1'b0;
		uart_rx1 <= 1'b0;
		uart_rx2 <= 1'b0;
		uart_rx3 <= 1'b0;
	end
	
	else begin 
		uart_rx0 <= uart_rx;
		uart_rx1 <= uart_rx0;
		uart_rx2 <= uart_rx1;
		uart_rx3 <= uart_rx2;
	end

assign neg_uart_rx = uart_rx3 & uart_rx2 & ~uart_rx1 & ~uart_rx0;

reg bps_start_r;
reg[3:0] num;


always @ (posedge clk or negedge rst_n)
	if(!rst_n)begin
		bps_start_r <= 1'bz;
		rx_int <= 1'b0;
	end
	
	else if(neg_uart_rx)begin 
		bps_start_r <= 1'b1;
		rx_int <= 1'b1;
	end
	
	else if(num==4'd9)begin
		bps_start_r <= 1'b0;
		rx_int <= 1'b0;
	end
	
assign bps_start = bps_start_r;

reg[7:0] rx_data_r;
reg[7:0] rx_temp_data;

always @ (posedge clk or negedge rst_n)
	if(!rst_n)begin 
		rx_temp_data <= 8'd0;
		num <= 4'd0;
		rx_data_r <= 8'd0;
	end
	
	else if(rx_int)begin 
		if(clk_bps)begin 
			num <= num+1'b1;
			case(num)
			4'd1:rx_temp_data[0] <= uart_rx;
			4'd2:rx_temp_data[1] <= uart_rx;
			4'd3:rx_temp_data[2] <= uart_rx;
			4'd4:rx_temp_data[3] <= uart_rx;
			4'd5:rx_temp_data[4] <= uart_rx;
			4'd6:rx_temp_data[5] <= uart_rx;
			4'd7:rx_temp_data[6] <= uart_rx;
			4'd8:rx_temp_data[7] <= uart_rx;
			default:;
			endcase
		end
		
		else if(num==4'd9)begin 
			num<=4'd0;
			rx_data_r <= rx_temp_data;
		end
		
	end

assign rx_data = rx_data_r;

endmodule



















