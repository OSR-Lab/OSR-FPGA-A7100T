`timescale 1ns / 1ps
// ============================================================================
// DES-64 ECB Encryption over UART
// Protocol:
//   Host sends 16 bytes: [key(8B)] + [plaintext(8B)]
//   FPGA replies 8 bytes: [ciphertext(8B)]
// UART: 115200 baud, 8N1
// LED: A13 (busy) = ON when out of reset
// ============================================================================
module recv_data (
    input  wire clk_50m_ext,
    output wire tx,
    input  wire rx,
    input  wire rst,
    output wire busy,
    output wire enc_only_trigger
);

// ---------------------------------------------------------------
// Clock / Reset (PLL: 50MHz -> 8MHz)
// ---------------------------------------------------------------
wire sys_clk;
wire pll_locked;
wire pll_clkfb;

MMCME2_BASE #(
    .CLKIN1_PERIOD   (20.000),     // 50MHz input
    .CLKFBOUT_MULT_F (16.0),      // VCO = 50 * 16 = 800MHz
    .CLKOUT0_DIVIDE_F(100.0),     // Output = 800 / 100 = 8MHz
    .DIVCLK_DIVIDE   (1)
) mmcm_inst (
    .CLKIN1   (clk_50m_ext),
    .CLKFBIN  (pll_clkfb),
    .CLKFBOUT (pll_clkfb),
    .CLKOUT0  (sys_clk),
    .LOCKED   (pll_locked),
    .PWRDWN   (1'b0),
    .RST      (1'b0),
    .CLKOUT0B (), .CLKOUT1  (), .CLKOUT1B (),
    .CLKOUT2  (), .CLKOUT2B (), .CLKOUT3  (), .CLKOUT3B (),
    .CLKOUT4  (), .CLKOUT5  (), .CLKOUT6  (), .CLKFBOUTB()
);

reg [3:0] rst_cnt = 4'h0;
wire sys_rst_n = rst_cnt[3];
always @(posedge sys_clk)
    if (!rst || !pll_locked) rst_cnt <= 4'h0;
    else if (!rst_cnt[3])    rst_cnt <= rst_cnt + 1'b1;

// ---------------------------------------------------------------
// UART
// ---------------------------------------------------------------
wire [7:0] rx_dout;
wire rx_busy;
wire tx_busy;
reg  wr_en_r;
reg  [7:0] tx_din;

uart communicator (
    .din(tx_din), .wr_en(wr_en_r), .clk_50m(sys_clk),
    .tx(tx), .tx_busy(tx_busy), .rx(rx),
    .rx_busy(rx_busy), .rst(sys_rst_n), .dout(rx_dout)
);

// ---------------------------------------------------------------
// RX edge detection: falling edge of rx_busy = 1 byte received
// ---------------------------------------------------------------
reg rx_busy_d;
wire rx_done = rx_busy_d & ~rx_busy;

always @(posedge sys_clk)
    rx_busy_d <= rx_busy;

// ---------------------------------------------------------------
// Receive buffer: 16 bytes [key(8) | plaintext(8)]
// ---------------------------------------------------------------
reg [7:0]  rx_buf [0:14]; // bytes 0..14 (byte 15 taken from rx_dout directly)
reg [4:0]  rx_cnt;        // 0..15

// ---------------------------------------------------------------
// DES instance
// ---------------------------------------------------------------
reg  [63:0] key_in_r;
reg  [63:0] data_in_r;
reg         des_start;
wire [63:0] des_data_out;
wire        des_done;
wire        des_busy;

des_core des_inst (
    .clk      (sys_clk),
    .rst_n    (sys_rst_n),
    .start    (des_start),
    .enc_dec  (1'b0),          // always encrypt
    .key_in   (key_in_r),
    .data_in  (data_in_r),
    .data_out (des_data_out),
    .done     (des_done),
    .busy     (des_busy)
);

// ---------------------------------------------------------------
// TX: send 8 bytes of ciphertext
// ---------------------------------------------------------------
reg [63:0] result_r;
reg [3:0]  tx_cnt;           // 0..8
reg        tx_busy_d;
wire       tx_done_pulse = tx_busy_d & ~tx_busy;

always @(posedge sys_clk)
    tx_busy_d <= tx_busy;

// ---------------------------------------------------------------
// Main FSM
// ---------------------------------------------------------------
localparam S_RECV  = 2'd0;
localparam S_START = 2'd1;
localparam S_WAIT  = 2'd2;
localparam S_SEND  = 2'd3;

reg [1:0] state;

always @(posedge sys_clk) begin
    if (!sys_rst_n) begin
        state     <= S_RECV;
        rx_cnt    <= 5'd0;
        des_start <= 1'b0;
        wr_en_r   <= 1'b0;
        tx_cnt    <= 4'd0;
    end else begin
        des_start <= 1'b0;
        wr_en_r   <= 1'b0;

        case (state)
            // ---- Receive 16 bytes: key(8) + plaintext(8) --------
            S_RECV: begin
                if (rx_done) begin
                    if (rx_cnt < 5'd15)
                        rx_buf[rx_cnt] <= rx_dout;
                    rx_cnt <= rx_cnt + 1'b1;
                    if (rx_cnt == 5'd15) begin
                        rx_cnt    <= 5'd0;
                        key_in_r  <= {rx_buf[0],rx_buf[1],rx_buf[2],rx_buf[3],
                                      rx_buf[4],rx_buf[5],rx_buf[6],rx_buf[7]};
                        data_in_r <= {rx_buf[8],rx_buf[9],rx_buf[10],rx_buf[11],
                                      rx_buf[12],rx_buf[13],rx_buf[14],rx_dout};
                        state <= S_START;
                    end
                end
            end

            // ---- DES start pulse --------------------------------
            S_START: begin
                des_start <= 1'b1;
                state     <= S_WAIT;
            end

            // ---- Wait for DES done ------------------------------
            S_WAIT: begin
                if (des_done) begin
                    result_r <= des_data_out;
                    tx_cnt   <= 4'd0;
                    state    <= S_SEND;
                end
            end

            // ---- Send 8 bytes MSB first -------------------------
            S_SEND: begin
                if (tx_cnt == 4'd0) begin
                    if (!tx_busy) begin
                        tx_din   <= result_r[63:56];
                        result_r <= {result_r[55:0], 8'h00};
                        wr_en_r  <= 1'b1;
                        tx_cnt   <= 4'd1;
                    end
                end else begin
                    if (tx_done_pulse) begin
                        if (tx_cnt == 4'd8) begin
                            state  <= S_RECV;
                            tx_cnt <= 4'd0;
                        end else begin
                            tx_din   <= result_r[63:56];
                            result_r <= {result_r[55:0], 8'h00};
                            wr_en_r  <= 1'b1;
                            tx_cnt   <= tx_cnt + 1'b1;
                        end
                    end
                end
            end
        endcase
    end
end

// ---------------------------------------------------------------
// LED
// ---------------------------------------------------------------
assign busy = sys_rst_n;
assign enc_only_trigger = (state == S_START) || (state == S_WAIT);

endmodule
