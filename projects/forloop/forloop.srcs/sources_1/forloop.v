`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module name: forloop
// Description: top module for for-loop power analysis
//   communicates with the host over UART, receives one byte as the loop count,
//   runs the for loop, and returns the final counter value.
//   a trigger output is asserted while the loop runs, for power analysis acquisition.
//
// Communication protocol:
//   Host sends 1 byte: [loop count N]
//   FPGA returns  1 byte: [final counter value = N]
//
// Main state machine flow:
//   S_RECV (receive 1 byte) -> S_LOOP (run the for loop) -> S_SEND (send the 1-byte result)
//   -> back to S_RECV to wait for the next data set
//
// LED indicator mapping:
//   A13 (busy)              = sys_rst_n        solid on after reset completes
//   A14 (rx_led)            = rx_busy          blinks during UART reception
//   A16 (loop_led)          = loop running     on while the for loop runs
//   A18 (tx_led)            = tx_busy          blinks during UART transmission
//   AB20 (trigger)          = loop trigger     on during the for loop only (power trace trigger)
//
// Ports:
//   ext_clock         - external clock input (J1 expansion header pin K19, driven by an external clock source)
//   tx                - UART serial transmit output
//   rx                - UART serial receive input
//   rst               - reset button (active low)
//   busy              - LED1: system running indicator
//   rx_led            - LED2: serial reception indicator
//   loop_led          - LED4: loop execution indicator
//   tx_led            - LED5: serial transmission indicator
//   trigger           - loop trigger output (for power analysis)
//////////////////////////////////////////////////////////////////////////////////
module forloop(
    input  wire ext_clock,
    output wire tx,
    input  wire rx,
    input  wire rst,
    output wire busy,
    output wire rx_led,
    output wire loop_led,
    output wire tx_led,
    output wire trigger
);

// ---------------------------------------------------------------
// Clock and reset
// ---------------------------------------------------------------
// the external clock (J1/K19) is used directly, with no PLL
wire sys_clk = ext_clock;

// reset synchronisation and delayed release: reset is released 8 clock cycles after the rst button is released
// rst_cnt[3] is used as a synchronous reset signal, active high (sys_rst_n)
reg [3:0] rst_cnt = 4'h0;
wire sys_rst_n = rst_cnt[3];
always @(posedge sys_clk)
    if (!rst)        rst_cnt <= 4'h0;           // the counter is cleared while the button is pressed
    else if (!rst_cnt[3]) rst_cnt <= rst_cnt + 1'b1;  // released after counting to 8 once the button is let go

// ---------------------------------------------------------------
// UART transceiver instance
// ---------------------------------------------------------------
wire [7:0] rx_dout;     // byte received over UART
wire rx_busy;           // UART receive busy flag
wire tx_busy;           // UART transmit busy flag
reg  wr_en_r;           // transmit write enable (single-cycle pulse)
reg  [7:0] tx_din;      // byte to be transmitted

uart communicator (
    .din(tx_din), .wr_en(wr_en_r), .clk_50m(sys_clk),
    .tx(tx), .tx_busy(tx_busy), .rx(rx),
    .rx_busy(rx_busy), .rst(sys_rst_n), .dout(rx_dout)
);

// ---------------------------------------------------------------
// receive completion detection: the falling edge of rx_busy = one full byte received
// ---------------------------------------------------------------
reg rx_busy_d;
wire rx_done = rx_busy_d & ~rx_busy;  // the falling edge of rx_busy generates a single-cycle pulse

always @(posedge sys_clk)
    rx_busy_d <= rx_busy;

// ---------------------------------------------------------------
// For loop counter
// ---------------------------------------------------------------
reg [7:0] loop_target;  // loop target value (received over UART)
reg [7:0] loop_cnt;     // loop counter (incremented every clock cycle)

// ---------------------------------------------------------------
// Main state machine
// ---------------------------------------------------------------
localparam S_RECV = 2'd0;  // receive 1 byte
localparam S_LOOP = 2'd1;  // run the for loop
localparam S_SEND = 2'd2;  // send the 1-byte result

reg [1:0] state;

always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
        state       <= S_RECV;
        wr_en_r     <= 1'b0;
        loop_target <= 8'd0;
        loop_cnt    <= 8'd0;
    end else begin
        // pulse signals default to zero
        wr_en_r <= 1'b0;

        case (state)
            // ---- Receive 1 byte -----------------------------------------
            // once a byte is received, use it as the loop target value
            S_RECV: begin
                if (rx_done) begin
                    loop_target <= rx_dout;   // latch the loop count
                    loop_cnt    <= 8'd0;      // clear the counter
                    state       <= S_LOOP;
                end
            end

            // ---- Run the for loop -----------------------------------------
            // the counter increments every clock cycle until it reaches the target
            // analogous to the STM32 loop for(i = 0; i < in; i++);
            S_LOOP: begin
                if (loop_cnt == loop_target) begin
                    state <= S_SEND;          // loop finished, move to the transmit state
                end else begin
                    loop_cnt <= loop_cnt + 1'b1;
                end
            end

            // ---- Send the 1-byte result -----------------------------------
            // return the final counter value to the host over UART
            S_SEND: begin
                if (!tx_busy) begin
                    tx_din  <= loop_cnt;      // send the final counter value
                    wr_en_r <= 1'b1;
                    state   <= S_RECV;        // return to the receive state and wait for the next request
                end
            end
        endcase
    end
end

// ---------------------------------------------------------------
// LED output mapping and trigger signal
// ---------------------------------------------------------------
assign busy     = sys_rst_n;                           // LED1: solid on after reset completes
assign rx_led   = rx_busy;                             // LED2: blinks during UART reception
assign loop_led = (state == S_LOOP);                   // LED4: on while the for loop runs
assign tx_led   = tx_busy;                             // LED5: blinks during UART transmission
assign trigger  = (state == S_LOOP);                   // asserted during the for loop only (power acquisition trigger)

endmodule
