`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module name: speed_setting
// Description: baud-rate generator providing the bit sampling clock for the UART transceiver
//   the divider comes from the system clock frequency and the target baud rate, and at the midpoint of each bit period
//   generates a single-cycle pulse (clk_bps).
//   - for the receiver: sampling at the midpoint gives the maximum noise margin
//   - for the transmitter: the midpoint trigger times each bit switch
//
// Parameter calculation (example: 8MHz / 115200bps):
//   BPS_PARA   = 8_000_000 / 115200 = 69 (clock cycles per bit)
//   BPS_PARA_2 = 69 / 2 = 34              (midpoint position)
//
// Ports:
//   clk       - system clock (8MHz, external clock on J1/K19)
//   rst_n     - asynchronous reset, active low
//   bps_start - start signal; the counter runs while high and is cleared while low
//   clk_bps   - baud-rate sampling pulse output, one single-clock pulse at the midpoint of each bit period
//////////////////////////////////////////////////////////////////////////////////
module speed_setting(
				input clk,
				input rst_n,
				input bps_start,
				output clk_bps
    );

// ---------- Baud-rate parameter definitions ----------
// CLK_PERIORD: system clock period (ns), 125ns means 8MHz
// BPS_SET:     baud rate / 100, i.e. 1152 means 115200 bps
// BPS_PARA:    divider count per bit = 10_000_000 / 125 / 1152 = 69
// BPS_PARA_2:  midpoint count = 69 / 2 = 34
// `define CLK_PERIORD     250  // Clock period in ns, 4MHz
// `define CLK_PERIORD     100  // Clock period in ns, 10MHz
// `define CLK_PERIORD     20   // Clock period in ns, 50MHz
`define CLK_PERIORD     125  // Clock period in ns, 8MHz (external clock from J1/K19)
`define BPS_SET         1152 // Baud rate / 100, 115200 bps

`define BPS_PARA        (10_000_000/`CLK_PERIORD/`BPS_SET)
`define BPS_PARA_2      (`BPS_PARA/2)

reg[12:0] cnt;       // divider counter, counting from 0 to BPS_PARA while bps_start is active
reg clk_bps_r;       // sampling pulse register
reg[2:0] uart_ctrl;  // baud rate select register (reserved, currently unused)

// counter logic: cleared when bps_start is inactive or the count is full, otherwise incremented
always @ (posedge clk or negedge rst_n)
        if(!rst_n) cnt<=13'd0;
        else if((cnt==`BPS_PARA) || !bps_start) cnt<=13'd0;
        else cnt<=cnt+1'b1;

// pulse generation: one single-cycle high pulse when the count reaches the midpoint BPS_PARA_2
always @ (posedge clk or negedge rst_n)
        if(!rst_n) clk_bps_r<=1'b0;
        else if(cnt==`BPS_PARA_2) clk_bps_r<=1'b1;
        else clk_bps_r<=1'b0;

assign clk_bps = clk_bps_r;

endmodule
