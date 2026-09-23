`timescale 1ns / 1ps
// Module: sm2_recv
// Description: SM2 top-level UART interface module.
//              Receives 96 bytes via UART:
//                [0..31]   private key d (256-bit, MSB first)
//                [32..63]  message hash e (256-bit, MSB first)
//                [64..95]  random nonce k (256-bit, MSB first)
//              Performs SM2 signing and transmits 64 bytes:
//                [0..31]   signature r (256-bit, MSB first)
//                [32..63]  signature s (256-bit, MSB first)
//              Architecture mirrors sm4_recv.v from sm4_A100t project.

module sm2_recv (
    input  wire clk_50m_ext,
    output wire tx,
    input  wire rx,
    input  wire rst,
    output wire busy,
    output reg  sign_start_trigger,
    output reg  wr_en
);

// Total input: 3 x 256-bit = 768 bits = 96 bytes
parameter TOTAL_IN_BYTES  = 16'd96;
parameter TOTAL_IN_BITS   = 16'd768;
// Total output: 2 x 256-bit = 512 bits = 64 bytes
parameter TOTAL_OUT_BYTES = 16'd64;
parameter TOTAL_OUT_BITS  = 16'd512;

parameter STATE_IDLE      = 3'b000;
parameter STATE_RECV      = 3'b001;
parameter STATE_SIGN      = 3'b010;
parameter STATE_SEND      = 3'b011;

reg  rdy_clr;
reg  [TOTAL_IN_BITS-1:0]  in_buffer;   // d || e || k
reg  [TOTAL_OUT_BITS-1:0] out_buffer;  // r || s (shifted out during SEND)
wire tx_busy;
wire rx_busy;
wire [7:0] dout;
reg  [2:0] state;
reg  [7:0] counter;

// SM2 signing interface signals
wire sign_busy;
wire sign_done;
wire [255:0] r_out, s_out;
reg  sign_start;

// Reason: No PLL approach — use 50MHz directly, software reset counter.
// Y22(rst) is tied to GND on TOE_X7CA100T, so rst is always 0.
wire sys_clk   = clk_50m_ext;
wire sys_rst_n;

reg [3:0] rst_cnt = 4'd0;
always @(posedge sys_clk) begin
    if (rst_cnt < 4'd15)
        rst_cnt <= rst_cnt + 4'd1;
end
assign sys_rst_n = (rst_cnt == 4'd15);

uart communicator (
    .din     (out_buffer[TOTAL_OUT_BITS-1:TOTAL_OUT_BITS-8]),
    .wr_en   (wr_en),
    .clk_50m (sys_clk),
    .tx      (tx),
    .tx_busy (tx_busy),
    .rx      (rx),
    .rx_busy (rx_busy),
    .rst     (sys_rst_n),
    .dout    (dout)
);

// SM2 signing core
// in_buffer layout: [767:512]=d, [511:256]=e, [255:0]=k (MSB first, shifted in)
sm2_sign_ctrl U_sign (
    .clk     (sys_clk),
    .rst_n   (sys_rst_n),
    .start_i (sign_start),
    .d_i     (in_buffer[TOTAL_IN_BITS-1   : TOTAL_IN_BITS-256]),  // [767:512] = d
    .e_i     (in_buffer[TOTAL_IN_BITS-257 : TOTAL_IN_BITS-512]),  // [511:256] = e
    .k_i     (in_buffer[255:0]),                                  // [255:0]   = k
    .r_o     (r_out),
    .s_o     (s_out),
    .done_o  (sign_done),
    .busy_o  (sign_busy)
);

assign busy = sign_busy | (state != STATE_IDLE);

// Combinational LED output
always @(state) begin
    case (state)
        STATE_SIGN: begin
            sign_start_trigger = 1'b1;
        end
        default: begin
            sign_start_trigger = 1'b0;
        end
    endcase
end

// Main FSM
always @(posedge sys_clk) begin
    if (~sys_rst_n) begin
        state      <= STATE_IDLE;
        in_buffer  <= {TOTAL_IN_BITS{1'b0}};
        out_buffer <= {TOTAL_OUT_BITS{1'b0}};
        counter    <= 8'b0;
        rdy_clr    <= 1'b0;
        wr_en      <= 1'b0;
        sign_start <= 1'b0;
    end else begin
        case (state)
            STATE_IDLE: begin
                counter    <= 8'b0;
                rdy_clr    <= 1'b0;
                wr_en      <= 1'b0;
                sign_start <= 1'b0;
                if (rx_busy)
                    state <= STATE_RECV;
                else
                    state <= STATE_IDLE;
            end

            STATE_RECV: begin
                sign_start <= 1'b0;
                if (counter < TOTAL_IN_BYTES) begin
                    if (rx_busy) begin
                        rdy_clr <= 1'b1;
                    end else if (rdy_clr) begin
                        rdy_clr    <= 1'b0;
                        in_buffer  <= {in_buffer[TOTAL_IN_BITS-1-8:0], dout};
                        counter    <= counter + 1'b1;
                    end else begin
                        state   <= STATE_RECV;
                        counter <= counter;
                    end
                end else begin
                    state      <= STATE_SIGN;
                    counter    <= 8'b0;
                    rdy_clr    <= 1'b0;
                    sign_start <= 1'b1;
                end
            end

            STATE_SIGN: begin
                sign_start <= 1'b0;
                if (sign_done) begin
                    // Load r||s into output buffer
                    out_buffer <= {r_out, s_out};
                    state      <= STATE_SEND;
                    counter    <= 8'b0;
                    wr_en      <= 1'b0;
                end else begin
                    state <= STATE_SIGN;
                end
            end

            STATE_SEND: begin
                if (counter < TOTAL_OUT_BYTES) begin
                    if (wr_en) begin
                        wr_en      <= 1'b0;
                        out_buffer <= {out_buffer[TOTAL_OUT_BITS-9:0], 8'b0};
                    end else if (!tx_busy) begin
                        wr_en   <= 1'b1;
                        counter <= counter + 1'b1;
                    end
                end else begin
                    state      <= STATE_IDLE;
                    counter    <= 8'b0;
                    rdy_clr    <= 1'b0;
                    wr_en      <= 1'b0;
                    sign_start <= 1'b0;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
