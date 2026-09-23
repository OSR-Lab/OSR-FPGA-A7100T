`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module name: recv_data
// Description: top module of the AES-128 ECB encryption system
//   Communicates with the host over UART, receives the key and plaintext, performs AES-128 encryption and returns the ciphertext.
//
// Communication protocol:
//   Host sends 32 bytes: [key, 16 bytes] + [plaintext, 16 bytes] (big-endian, first byte = most significant)
//   FPGA returns  16 bytes: [ciphertext, 16 bytes] (big-endian, MSB sent first)
//
// Main state machine flow:
//   S_RECV (receive 32 bytes) -> S_KEY_EXP (start key expansion) -> S_WAIT_KEY (wait for expansion)
//   -> S_ENCRYPT (start encryption) -> S_WAIT_ENC (wait for encryption) -> S_SEND (send the 16-byte ciphertext)
//   -> back to S_RECV to wait for the next data set
//
// LED indicator mapping:
//   A13 (busy)              = sys_rst_n        solid on after reset completes
//   A14 (key_exp_trigger)   = rx_busy          blinks during UART reception
//   A16 (enc_start_trigger) = aes_busy         on during AES activity (key expansion + encryption)
//   A18 (wr_en)             = tx_busy          blinks during UART transmission
//   AB20 (enc_only_trigger) = encryption flag  on during the encryption phase only (power trace trigger)
//
// Ports:
//   clk_50m_ext       - 50MHz external clock input (divided down to 8MHz by the PLL before use)
//   tx                - UART serial transmit output
//   rx                - UART serial receive input
//   rst               - reset button (active low)
//   busy              - LED1: system running indicator
//   key_exp_trigger   - LED2: serial reception indicator
//   enc_start_trigger - LED4: AES activity indicator
//   wr_en             - LED5: serial transmission indicator
//   enc_only_trigger  - encryption trigger output (for power analysis)
//////////////////////////////////////////////////////////////////////////////////
module recv_data(
    input  wire clk_50m_ext,
    output wire tx,
    input  wire rx,
    input  wire rst,
    output wire busy,
    output wire key_exp_trigger,
    output wire enc_start_trigger,
    output wire wr_en,
    output wire enc_only_trigger
);

// ---------------------------------------------------------------
// Clock and reset (PLL: 50MHz -> 8MHz)
// ---------------------------------------------------------------
wire sys_clk;        // PLL output, 8MHz system clock
wire pll_locked;     // PLL lock flag
wire pll_clkfb;      // PLL feedback clock

MMCME2_BASE #(
    .CLKIN1_PERIOD   (20.000),     // input clock period 20ns = 50MHz
    .CLKFBOUT_MULT_F (16.0),      // VCO = 50 * 16 = 800MHz
    .CLKOUT0_DIVIDE_F(100.0),     // output = 800 / 100 = 8MHz
    .DIVCLK_DIVIDE   (1)
) mmcm_inst (
    .CLKIN1   (clk_50m_ext),
    .CLKFBIN  (pll_clkfb),
    .CLKFBOUT (pll_clkfb),
    .CLKOUT0  (sys_clk),
    .LOCKED   (pll_locked),
    .PWRDWN   (1'b0),
    .RST      (1'b0),
    // unused outputs
    .CLKOUT0B (),
    .CLKOUT1  (), .CLKOUT1B (),
    .CLKOUT2  (), .CLKOUT2B (),
    .CLKOUT3  (), .CLKOUT3B (),
    .CLKOUT4  (), .CLKOUT5  (), .CLKOUT6  (),
    .CLKFBOUTB()
);

// reset synchronisation and delayed release: reset is released 8 clock cycles after the rst button is released and the PLL is locked
// rst_cnt[3] is used as a synchronous reset signal, active high (sys_rst_n)
reg [3:0] rst_cnt = 4'h0;
wire sys_rst_n = rst_cnt[3];
always @(posedge sys_clk)
    if (!rst || !pll_locked) rst_cnt <= 4'h0;   // cleared while the button is pressed or the PLL is unlocked
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
// receive buffer: 32 bytes [key (16 bytes) | plaintext (16 bytes)]
// ---------------------------------------------------------------
// rx_buf[0..30] holds the first 31 bytes; the 32nd byte (rx_dout) is used directly when the counter reaches 31
reg [7:0]  rx_buf [0:30];
reg [5:0]  rx_cnt;          // byte counter 0..31

// ---------------------------------------------------------------
// AES-128 encryption core instance
// ---------------------------------------------------------------
reg  [127:0] key_in_r;      // 128-bit key register
reg  [127:0] text_in_r;     // 128-bit plaintext register
reg          aes_key_exp;   // key expansion trigger pulse
reg          aes_start;     // encryption start pulse
wire         aes_key_val;   // key expansion done flag
wire         aes_text_val;  // encryption done flag (ciphertext valid)
wire [127:0] aes_text_out;  // 128-bit ciphertext output
wire         aes_busy_w;    // AES core busy flag

aes128 aes_core (
    .resetn      (sys_rst_n),
    .clock       (sys_clk),
    .enc_dec     (1'b0),        // fixed to encryption mode (0 = encrypt, 1 = decrypt)
    .key_exp     (aes_key_exp),
    .start       (aes_start),
    .key_val     (aes_key_val),
    .text_val    (aes_text_val),
    .key_in      (key_in_r),
    .text_in     (text_in_r),
    .text_out    (aes_text_out),
    .busy        (aes_busy_w)
);

// ---------------------------------------------------------------
// Transmit control: send the 128-bit ciphertext one byte at a time, MSB first (16 bytes)
// ---------------------------------------------------------------
reg [127:0] cipher_r;       // ciphertext shift register, shifted left after each most significant byte is sent
reg [4:0]   tx_cnt;         // transmit byte counter 0..16
reg         tx_busy_d;
wire        tx_done_pulse = tx_busy_d & ~tx_busy;  // the falling edge of tx_busy = one byte finished transmitting

always @(posedge sys_clk)
    tx_busy_d <= tx_busy;

// ---------------------------------------------------------------
// Main state machine
// ---------------------------------------------------------------
localparam S_RECV     = 3'd0;  // receive 32 bytes
localparam S_KEY_EXP  = 3'd1;  // issue the key expansion pulse
localparam S_WAIT_KEY = 3'd2;  // wait for key expansion to finish (10 rounds)
localparam S_ENCRYPT  = 3'd3;  // issue the encryption start pulse
localparam S_WAIT_ENC = 3'd4;  // wait for encryption to finish (10 rounds)
localparam S_SEND     = 3'd5;  // send the 16-byte ciphertext

reg [2:0] state;

always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
        state       <= S_RECV;
        rx_cnt      <= 6'd0;
        aes_key_exp <= 1'b0;
        aes_start   <= 1'b0;
        wr_en_r     <= 1'b0;
        tx_cnt      <= 5'd0;
    end else begin
        // pulse signals default to zero and go high for one cycle only when needed
        aes_key_exp <= 1'b0;
        aes_start   <= 1'b0;
        wr_en_r     <= 1'b0;

        case (state)
            // ---- Receive 32 bytes ------------------------------------
            // every received byte (rx_done pulse) is stored in the buffer
            // when the 32nd byte arrives, pack the buffer into the 128-bit key and plaintext
            S_RECV: begin
                if (rx_done) begin
                    if (rx_cnt < 6'd31)
                        rx_buf[rx_cnt] <= rx_dout;
                    rx_cnt <= rx_cnt + 1'b1;
                    if (rx_cnt == 6'd31) begin
                        rx_cnt <= 6'd0;
                        // big-endian packing: byte 0 = most significant
                        // key: rx_buf[0..15] -> key_in_r[127:0]
                        key_in_r  <= {rx_buf[0],rx_buf[1],rx_buf[2],rx_buf[3],
                                      rx_buf[4],rx_buf[5],rx_buf[6],rx_buf[7],
                                      rx_buf[8],rx_buf[9],rx_buf[10],rx_buf[11],
                                      rx_buf[12],rx_buf[13],rx_buf[14],rx_buf[15]};
                        // plaintext: rx_buf[16..30] + rx_dout (byte 31) -> text_in_r[127:0]
                        text_in_r <= {rx_buf[16],rx_buf[17],rx_buf[18],rx_buf[19],
                                      rx_buf[20],rx_buf[21],rx_buf[22],rx_buf[23],
                                      rx_buf[24],rx_buf[25],rx_buf[26],rx_buf[27],
                                      rx_buf[28],rx_buf[29],rx_buf[30],rx_dout};
                        state <= S_KEY_EXP;
                    end
                end
            end

            // ---- Start key expansion -----------------------------------
            S_KEY_EXP: begin
                aes_key_exp <= 1'b1;    // single-cycle pulse that starts key expansion
                state       <= S_WAIT_KEY;
            end

            // ---- Wait for key expansion to finish ------------------------
            S_WAIT_KEY: begin
                if (aes_key_val) state <= S_ENCRYPT;  // key_val goes high when the 10 expansion rounds are done
            end

            // ---- Start encryption ----------------------------------------
            S_ENCRYPT: begin
                aes_start <= 1'b1;      // single-cycle pulse that starts encryption
                state     <= S_WAIT_ENC;
            end

            // ---- Wait for encryption to finish -------------------------------
            S_WAIT_ENC: begin
                if (aes_text_val) begin  // text_val goes high when the 10 encryption rounds are done
                    cipher_r <= aes_text_out;  // latch the 128-bit ciphertext
                    tx_cnt   <= 5'd0;
                    state    <= S_SEND;
                end
            end

            // ---- Send the 16-byte ciphertext (MSB first) ----------------------
            // Transmit behaviour: tx_busy goes high one cycle after wr_en,
            // therefore tx_done_pulse (the falling edge of tx_busy) starts each following byte
            S_SEND: begin
                if (tx_cnt == 5'd0) begin
                    // first byte: sent immediately while the UART is idle
                    if (!tx_busy) begin
                        tx_din  <= cipher_r[127:120];           // take the most significant byte
                        cipher_r<= {cipher_r[119:0], 8'h00};   // shift left by 8 bits
                        wr_en_r <= 1'b1;
                        tx_cnt  <= 5'd1;
                    end
                end else begin
                    // following bytes: wait until the previous byte has been sent
                    if (tx_done_pulse) begin
                        if (tx_cnt == 5'd16) begin
                            state  <= S_RECV;   // all 16 bytes sent, return to the receive state
                            tx_cnt <= 5'd0;
                        end else begin
                            tx_din  <= cipher_r[127:120];
                            cipher_r<= {cipher_r[119:0], 8'h00};
                            wr_en_r <= 1'b1;
                            tx_cnt  <= tx_cnt + 1'b1;
                        end
                    end
                end
            end
        endcase
    end
end

// ---------------------------------------------------------------
// LED output mapping
// ---------------------------------------------------------------
assign busy              = sys_rst_n;       // LED1: solid on after reset completes
assign key_exp_trigger   = rx_busy;         // LED2: blinks during UART reception
assign enc_start_trigger = aes_busy_w;      // LED4: on during AES activity
assign wr_en             = tx_busy;         // LED5: blinks during UART transmission
assign enc_only_trigger  = (state == S_ENCRYPT) || (state == S_WAIT_ENC);  // asserted during the encryption phase only

endmodule
