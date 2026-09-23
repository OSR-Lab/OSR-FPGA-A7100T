`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module name: uart
// Description: top-level UART wrapper module
//   this module wraps the UART receiver (my_uart_rx), the transmitter (my_uart_tx) and their separate
//   baud-rate generators (speed_setting) together, exposing a simple transceiver interface.
//   reception and transmission each have their own baud-rate clock, so they do not interfere.
//
// Signal flow:
//   receive path: rx pin -> my_uart_rx (sampled by clk_bps1) -> dout[7:0] output
//   transmit path: din[7:0] + wr_en pulse -> my_uart_tx (timed by clk_bps2) -> tx pin
//
// Ports:
//   din[7:0]  - 8-bit data to transmit
//   wr_en     - write enable; its rising edge triggers one transmission
//   clk_50m   - system clock (actually the 8MHz PLL output; the port name is kept for compatibility)
//   tx        - UART serial transmit output pin
//   tx_busy   - transmit busy flag, high while transmitting
//   rx        - UART serial receive input pin
//   rx_busy   - receive busy flag, high while receiving
//   rst       - asynchronous reset, active low
//   dout[7:0] - 8-bit received data
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

// ---------- Internal wiring ----------
wire bps_start1,bps_start2;  // start signals of the receive/transmit baud-rate generators
wire clk_bps1,clk_bps2;      // receive/transmit baud-rate sampling clock pulses

wire[7:0] rx_data;
wire rx_int;
wire wr_en_neg;


// ---------- Baud-rate generator for the receive channel ----------
// while bps_start1 is active, clk_bps1 sampling pulses are produced for the receiver
speed_setting speed_rx(
						.clk(clk_50m),
						.rst_n(rst),
						.bps_start(bps_start1),
						.clk_bps(clk_bps1)
						);

// ---------- UART receiver instance ----------
// the baud-rate generator starts once a start bit is detected, sampling happens at each bit midpoint, and dout is output when reception completes
my_uart_rx	my_uart_rx_r(
						.clk(clk_50m),
						.rst_n(rst),
						.uart_rx(rx),
						.rx_data(dout),
						.rx_int(rx_busy),
						.clk_bps(clk_bps1),
						.bps_start(bps_start1));


// ---------- Baud-rate generator for the transmit channel ----------
// while bps_start2 is active, clk_bps2 timing pulses are produced for the transmitter
speed_setting speed_tx(
						.clk(clk_50m),
						.rst_n(rst),
						.bps_start(bps_start2),
						.clk_bps(clk_bps2)
						);

// ---------- UART transmitter instance ----------
// a wr_en pulse latches din and starts transmission; tx_busy stays high while transmitting
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

