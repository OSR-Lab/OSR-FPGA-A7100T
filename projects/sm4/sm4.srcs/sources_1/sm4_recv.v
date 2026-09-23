`timescale 1ns / 1ps
// Module: sm4_recv
// Description: SM4-128 top-level module. Receives 32 bytes via UART
//              (16 bytes key + 16 bytes plaintext), performs SM4-128
//              encryption, then sends the 16-byte ciphertext back via UART.
//              Architecture mirrors recv_data.v from aes_A100t project.

module sm4_recv (
    input  wire clk_50m_ext,
    output wire tx,
    input  wire rx,
    input  wire rst,
    output wire busy,
    output reg  key_exp_trigger,
    output reg  enc_start_trigger,
    output reg  wr_en,
    output wire enc_only_trigger
);

parameter DATA_SIZE       = 16'd128;
parameter DATA_SIZE_BYTE  = 16'd16;
parameter KEY_SIZE        = 16'd128;
parameter TOTLE_SIZE      = 16'd256;   // Total (key + data) in bits
parameter TOTLE_SIZE_BYTE = 16'd32;    // Total (key + data) in bytes

parameter STATE_IDLE         = 3'b000;
parameter STATE_RECV         = 3'b001;
parameter STATE_KEY_GEN      = 3'b010;
parameter STATE_ENC          = 3'b011;
parameter STATE_SEND         = 3'b100;
parameter STATE_KEY_GEN_WAIT = 3'b110;

// PLL: 50MHz -> 8MHz
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
    else if (!rst_cnt[3]) rst_cnt <= rst_cnt + 1'b1;

reg  rdy_clr;
reg  [TOTLE_SIZE-1:0] buffer;
wire tx_busy;
wire rx_busy;
wire [7:0] dout;
reg  [2:0] state;
reg  [7:0] counter;

reg  key_exp;
reg  enc_start;
wire enc_dec;
wire key_val;
wire text_val;
wire [DATA_SIZE-1:0] text_out;

assign enc_dec = 1'b0;

uart communicator (
    .din     (buffer[DATA_SIZE-1:DATA_SIZE-8]),
    .wr_en   (wr_en),
    .clk_50m (sys_clk),
    .tx      (tx),
    .tx_busy (tx_busy),
    .rx      (rx),
    .rx_busy (rx_busy),
    .rst     (sys_rst_n),
    .dout    (dout)
);

sm4_core sm4_unit (
    .clk     (sys_clk),
    .reset_n (sys_rst_n),
    .key_exp (key_exp),
    .start   (enc_start),
    .key_in  (buffer[DATA_SIZE+KEY_SIZE-1:DATA_SIZE]),
    .text_in (buffer[DATA_SIZE-1:0]),
    .text_out(text_out),
    .key_val (key_val),
    .text_val(text_val),
    .busy    (busy)
);

// Combinational LED outputs based on state
always @(state) begin
    case (state)
        STATE_KEY_GEN: begin
            key_exp_trigger   = 1'b1;
            enc_start_trigger = 1'b0;
        end
        STATE_ENC: begin
            key_exp_trigger   = 1'b0;
            enc_start_trigger = 1'b1;
        end
        default: begin
            key_exp_trigger   = 1'b0;
            enc_start_trigger = 1'b0;
        end
    endcase
end

// Main FSM
always @(posedge sys_clk) begin
    if (~sys_rst_n) begin
        state     <= STATE_IDLE;
        buffer    <= 0;
        counter   <= 8'b0;
        rdy_clr   <= 1'b0;
        wr_en     <= 1'b0;
        enc_start <= 1'b0;
        key_exp   <= 1'b0;
    end else begin
        case (state)
            STATE_IDLE: begin
                counter   <= 8'b0;
                rdy_clr   <= 1'b0;
                wr_en     <= 1'b0;
                enc_start <= 1'b0;
                key_exp   <= 1'b0;
                if (rx_busy)
                    state <= STATE_RECV;
                else
                    state <= STATE_IDLE;
            end

            STATE_RECV: begin
                enc_start <= 1'b0;
                if (counter < TOTLE_SIZE_BYTE) begin
                    if (rx_busy) begin
                        rdy_clr <= 1'b1;
                    end else if (rdy_clr) begin
                        rdy_clr <= 1'b0;
                        buffer  <= {buffer[TOTLE_SIZE-1-8:0], dout};
                        counter <= counter + 1'b1;
                    end else begin
                        state   <= STATE_RECV;
                        buffer  <= buffer;
                        counter <= counter;
                    end
                end else begin
                    state   <= STATE_KEY_GEN_WAIT;
                    counter <= 8'b0;
                    rdy_clr <= 1'b0;
                    key_exp <= 1'b1;
                end
            end

            STATE_KEY_GEN_WAIT: begin
                state   <= STATE_KEY_GEN;
                key_exp <= 1'b0;
            end

            STATE_KEY_GEN: begin
                if (key_val) begin
                    state     <= STATE_ENC;
                    enc_start <= 1'b1;
                end else begin
                    state     <= STATE_KEY_GEN;
                    enc_start <= 1'b0;
                end
            end

            STATE_ENC: begin
                enc_start <= 1'b0;
                if (text_val) begin
                    buffer[DATA_SIZE-1:0] <= text_out;
                    state   <= STATE_SEND;
                    counter <= 8'b0;
                    wr_en   <= 1'b0;
                end
            end

            STATE_SEND: begin
                if (counter < DATA_SIZE_BYTE) begin
                    if (wr_en) begin
                        wr_en  <= 1'b0;
                        buffer <= {buffer[DATA_SIZE-9:0], 8'b0};
                    end else if (!tx_busy) begin
                        wr_en   <= 1'b1;
                        counter <= counter + 1'b1;
                    end
                end else begin
                    state     <= STATE_IDLE;
                    counter   <= 8'b0;
                    rdy_clr   <= 1'b0;
                    wr_en     <= 1'b0;
                    enc_start <= 1'b0;
                    key_exp   <= 1'b0;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

// Encryption-only trigger: high only during STATE_ENC (for power trace capture)
assign enc_only_trigger = (state == STATE_ENC);

endmodule
