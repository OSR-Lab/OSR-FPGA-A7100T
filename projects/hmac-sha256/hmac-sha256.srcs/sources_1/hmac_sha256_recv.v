`timescale 1ns / 1ps
`default_nettype wire

// Module: hmac_sha256_recv
// Description: HMAC-SHA256 top-level UART interface module.
//              Receives 32 bytes (16B key + 16B message) via UART,
//              computes HMAC-SHA256 using sha256_core (secworks),
//              then transmits 32 bytes (256-bit HMAC digest) back via UART.
//
// HMAC(K, m) = SHA256((K' ^ opad) || SHA256((K' ^ ipad) || m))
//   K' = K zero-padded to 64 bytes (key is 16 bytes)
//   ipad = 0x36 repeated 64 times
//   opad = 0x5c repeated 64 times
//
// sha256_core is called 4 times (4 blocks):
//   Block 1 (init): K' ^ ipad                              (64B)
//   Block 2 (next): msg || padding, len=0x280               (64B) -> inner digest
//   Block 3 (init): K' ^ opad                              (64B)
//   Block 4 (next): inner_digest || padding, len=0x300      (64B) -> HMAC
//
// UART protocol (115200 baud, 8MHz clock via PLL):
//   Receive:  32 bytes = 16B key + 16B message (MSB first)
//   Transmit: 32 bytes = HMAC-SHA256 digest (MSB first)

module hmac_sha256_recv (
    input  wire clk_50m_ext,
    output wire tx,
    input  wire rx,
    input  wire rst,
    output wire busy,
    output wire enc_only_trigger
);

parameter TOTAL_IN_BYTES  = 8'd32;  // 16B key + 16B message
parameter TOTAL_OUT_BYTES = 8'd32;  // 256-bit HMAC digest

localparam STATE_IDLE        = 4'd0;
localparam STATE_RECV        = 4'd1;
localparam STATE_HASH_IPAD   = 4'd2;
localparam STATE_WAIT1       = 4'd3;
localparam STATE_HASH_MSG    = 4'd4;
localparam STATE_WAIT2       = 4'd5;
localparam STATE_HASH_OPAD   = 4'd6;
localparam STATE_WAIT3       = 4'd7;
localparam STATE_HASH_DIGEST = 4'd8;
localparam STATE_WAIT4       = 4'd9;
localparam STATE_SEND        = 4'd10;

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

reg         rdy_clr;
reg [127:0] key_reg;       // 16-byte key
reg [127:0] msg_reg;       // 16-byte message
reg [255:0] out_buffer;    // 256-bit digest (shifted out during SEND)
reg [255:0] inner_digest;  // store inner hash result
wire        tx_busy;
wire        rx_busy;
wire [7:0]  dout;
reg  [3:0]  state;
reg  [7:0]  counter;
reg         wr_en;

// Flag: set once digest_valid goes low after launching a hash,
// prevents acting on stale digest_valid from a previous step
reg         dv_cleared;

// sha256_core control signals
reg          sha_init;
reg          sha_next;
reg [511:0]  sha_block;
wire         sha_ready;
wire         sha_digest_valid;
wire [255:0] sha_digest;

sha256_core U_sha256 (
    .clk          (sys_clk),
    .reset_n      (sys_rst_n),
    .init         (sha_init),
    .next         (sha_next),
    .mode         (1'b1),        // mode=1 selects SHA-256
    .block        (sha_block),
    .ready        (sha_ready),
    .digest       (sha_digest),
    .digest_valid (sha_digest_valid)
);

uart communicator (
    .din     (out_buffer[255:248]),
    .wr_en   (wr_en),
    .clk_50m (sys_clk),
    .tx      (tx),
    .tx_busy (tx_busy),
    .rx      (rx),
    .rx_busy (rx_busy),
    .rst     (sys_rst_n),
    .dout    (dout)
);

assign busy = (state != STATE_IDLE);

// Encryption-only trigger: high during HMAC hash computation (4 blocks), excludes UART RX/TX
assign enc_only_trigger = (state >= STATE_HASH_IPAD) && (state <= STATE_WAIT4);

// Construct K' XOR ipad block (512 bits)
// K'[0..15] = key, K'[16..63] = 0x00
// ipad = 0x36 repeated 64 times
// First 16 bytes: key ^ 0x36, remaining 48 bytes: 0x00 ^ 0x36 = 0x36
wire [511:0] ipad_block;
genvar i;
generate
    for (i = 0; i < 16; i = i + 1) begin : gen_ipad
        assign ipad_block[511 - i*8 -: 8] = key_reg[127 - i*8 -: 8] ^ 8'h36;
    end
endgenerate
assign ipad_block[383:0] = {48{8'h36}};

// Construct K' XOR opad block (512 bits)
// First 16 bytes: key ^ 0x5c, remaining 48 bytes: 0x00 ^ 0x5c = 0x5c
wire [511:0] opad_block;
generate
    for (i = 0; i < 16; i = i + 1) begin : gen_opad
        assign opad_block[511 - i*8 -: 8] = key_reg[127 - i*8 -: 8] ^ 8'h5c;
    end
endgenerate
assign opad_block[383:0] = {48{8'h5c}};

// Construct message block with SHA-256 padding (512 bits)
// msg (16B) || 0x80 || 0x00*39 || 64-bit length (0x0000_0000_0000_0280)
// Total message length for inner hash = (64 + 16) * 8 = 640 = 0x280
// 128 + 8 + 312 + 64 = 512
wire [511:0] msg_block;
assign msg_block = {msg_reg, 8'h80, 312'b0, 64'h0000_0000_0000_0280};

// Construct inner digest block with SHA-256 padding (512 bits)
// inner_digest (32B) || 0x80 || 0x00*23 || 64-bit length (0x0000_0000_0000_0300)
// Total message length for outer hash = (64 + 32) * 8 = 768 = 0x300
// 256 + 8 + 184 + 64 = 512
wire [511:0] digest_block;
assign digest_block = {inner_digest, 8'h80, 184'b0, 64'h0000_0000_0000_0300};

// Main FSM
always @(posedge sys_clk) begin
    if (~sys_rst_n) begin
        state        <= STATE_IDLE;
        key_reg      <= 128'b0;
        msg_reg      <= 128'b0;
        out_buffer   <= 256'b0;
        inner_digest <= 256'b0;
        counter      <= 8'b0;
        rdy_clr      <= 1'b0;
        wr_en        <= 1'b0;
        sha_init     <= 1'b0;
        sha_next     <= 1'b0;
        sha_block    <= 512'b0;
        dv_cleared   <= 1'b0;
    end else begin

        // Default: deassert pulse signals each cycle
        sha_init <= 1'b0;
        sha_next <= 1'b0;
        wr_en    <= 1'b0;

        case (state)
            // -----------------------------------------------------------
            STATE_IDLE: begin
                counter <= 8'b0;
                rdy_clr <= 1'b0;
                if (rx_busy)
                    state <= STATE_RECV;
            end

            // -----------------------------------------------------------
            // Collect 32 bytes: first 16 -> key_reg, next 16 -> msg_reg
            STATE_RECV: begin
                if (counter < TOTAL_IN_BYTES) begin
                    if (rx_busy) begin
                        rdy_clr <= 1'b1;
                    end else if (rdy_clr) begin
                        rdy_clr <= 1'b0;
                        if (counter < 8'd16)
                            key_reg <= {key_reg[119:0], dout};
                        else
                            msg_reg <= {msg_reg[119:0], dout};
                        counter <= counter + 1'b1;
                    end
                end else begin
                    // All 32 bytes received -> start HMAC
                    state <= STATE_HASH_IPAD;
                    $display("[%0t] RECV done: key=%032h msg=%032h", $time, key_reg, msg_reg);
                end
            end

            // -----------------------------------------------------------
            // Step 1: Feed K' XOR ipad block (init)
            STATE_HASH_IPAD: begin
                sha_block  <= ipad_block;
                sha_init   <= 1'b1;
                dv_cleared <= 1'b0;
                state      <= STATE_WAIT1;
                $display("[%0t] HASH_IPAD: block=%0128h", $time, ipad_block);
            end

            // Wait for sha256_core to finish block 1
            // Two-phase: first wait for digest_valid to deassert (core started),
            // then wait for it to assert (core finished)
            STATE_WAIT1: begin
                if (!dv_cleared) begin
                    if (!sha_digest_valid)
                        dv_cleared <= 1'b1;
                end else if (sha_digest_valid)
                    state <= STATE_HASH_MSG;
                    // Expected after ipad block: intermediate (no Python equivalent for single block)
            end

            // -----------------------------------------------------------
            // Step 2: Feed message block with padding (next)
            STATE_HASH_MSG: begin
                sha_block  <= msg_block;
                sha_next   <= 1'b1;
                dv_cleared <= 1'b0;
                state      <= STATE_WAIT2;
                $display("[%0t] HASH_MSG: block=%0128h", $time, msg_block);
            end

            // Wait for sha256_core to finish block 2 -> inner digest
            STATE_WAIT2: begin
                if (!dv_cleared) begin
                    if (!sha_digest_valid)
                        dv_cleared <= 1'b1;
                end else if (sha_digest_valid) begin
                    inner_digest <= sha_digest;
                    state        <= STATE_HASH_OPAD;
                    $display("[%0t] WAIT2 done (inner digest): %064h", $time, sha_digest);
                    // Expected: 942a43465509d6b78d35b197c489465d7b3c202066d01a4979f7bb46d5edd070
                end
            end

            // -----------------------------------------------------------
            // Step 3: Feed K' XOR opad block (init)
            STATE_HASH_OPAD: begin
                sha_block  <= opad_block;
                sha_init   <= 1'b1;
                dv_cleared <= 1'b0;
                state      <= STATE_WAIT3;
                $display("[%0t] HASH_OPAD: block=%0128h", $time, opad_block);
            end

            // Wait for sha256_core to finish block 3
            STATE_WAIT3: begin
                if (!dv_cleared) begin
                    if (!sha_digest_valid)
                        dv_cleared <= 1'b1;
                end else if (sha_digest_valid)
                    state <= STATE_HASH_DIGEST;
            end

            // -----------------------------------------------------------
            // Step 4: Feed inner_digest block with padding (next)
            STATE_HASH_DIGEST: begin
                sha_block  <= digest_block;
                sha_next   <= 1'b1;
                dv_cleared <= 1'b0;
                state      <= STATE_WAIT4;
                $display("[%0t] HASH_DIGEST: block=%0128h", $time, digest_block);
            end

            // Wait for sha256_core to finish block 4 -> HMAC result
            STATE_WAIT4: begin
                if (!dv_cleared) begin
                    if (!sha_digest_valid)
                        dv_cleared <= 1'b1;
                end else if (sha_digest_valid) begin
                    out_buffer <= sha_digest;
                    state      <= STATE_SEND;
                    counter    <= 8'b0;
                    $display("[%0t] WAIT4 done (HMAC result): %064h", $time, sha_digest);
                    // Expected: 32cd28477b88c12e515b0e1fd7330d19616a4a51f6c502d64fe6a93fe7f786fa
                end
            end

            // -----------------------------------------------------------
            // Transmit 32 bytes of HMAC digest (MSB first)
            STATE_SEND: begin
                if (counter < TOTAL_OUT_BYTES) begin
                    if (wr_en) begin
                        // uart already latched out_buffer[255:248]; now shift
                        out_buffer <= {out_buffer[247:0], 8'b0};
                    end else if (!tx_busy) begin
                        wr_en   <= 1'b1;
                        counter <= counter + 1'b1;
                    end
                end else begin
                    state   <= STATE_IDLE;
                    counter <= 8'b0;
                    rdy_clr <= 1'b0;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
