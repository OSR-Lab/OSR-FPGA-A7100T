`timescale 1ns / 1ps
// GB/T 32907-2016 SM4-128 ECB test vector:
//   Key:        0123456789ABCDEFFEDCBA9876543210
//   Plaintext:  0123456789ABCDEFFEDCBA9876543210
//   Ciphertext: 681EDF34D206965E86B3E94F536E4246 (expected)

module tb_sm4_recv;

reg        clk_50m_ext;
reg        rx;
reg        rst;
wire       tx;
wire       busy;
wire       key_exp_trigger;
wire       enc_start_trigger;
wire       wr_en;

sm4_recv u_sm4_recv (
    .clk_50m_ext      (clk_50m_ext),
    .tx               (tx),
    .rx               (rx),
    .rst              (rst),
    .busy             (busy),
    .key_exp_trigger  (key_exp_trigger),
    .enc_start_trigger(enc_start_trigger),
    .wr_en            (wr_en)
);

// 50MHz clock
initial clk_50m_ext = 0;
always #10 clk_50m_ext = ~clk_50m_ext;

// 115200 baud = 8680ns per bit
`define BIT_PERIOD 8680

// UART send task (LSB first, 1 start + 8 data + 1 stop)
task uart_send_byte;
    input [7:0] data;
    integer i;
    begin
        rx = 0; #`BIT_PERIOD;           // start bit
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i]; #`BIT_PERIOD; // data bits LSB first
        end
        rx = 1; #`BIT_PERIOD;           // stop bit
    end
endtask

// UART receive task: sample at mid-bit, 115200 baud
task uart_recv_byte;
    output [7:0] data;
    integer i;
    begin
        // Wait for start bit (falling edge on tx)
        @(negedge tx);
        #(`BIT_PERIOD + `BIT_PERIOD/2); // skip start bit, land at mid of bit0
        for (i = 0; i < 8; i = i + 1) begin
            data[i] = tx;
            #`BIT_PERIOD;
        end
        // stop bit consumed automatically by next @(negedge tx)
    end
endtask

integer k;
reg [7:0] rx_byte [0:15];

initial begin
    rx  = 1;
    rst = 0;
    #200;
    rst = 1;

    // Wait for internal power-on reset counter to complete (8 cycles * 20ns)
    #500;

    $display("Sending Key: 01 23 45 67 89 AB CD EF FE DC BA 98 76 54 32 10");
    uart_send_byte(8'h01); uart_send_byte(8'h23);
    uart_send_byte(8'h45); uart_send_byte(8'h67);
    uart_send_byte(8'h89); uart_send_byte(8'hab);
    uart_send_byte(8'hcd); uart_send_byte(8'hef);
    uart_send_byte(8'hfe); uart_send_byte(8'hdc);
    uart_send_byte(8'hba); uart_send_byte(8'h98);
    uart_send_byte(8'h76); uart_send_byte(8'h54);
    uart_send_byte(8'h32); uart_send_byte(8'h10);

    $display("Sending Plaintext: 01 23 45 67 89 AB CD EF FE DC BA 98 76 54 32 10");
    uart_send_byte(8'h01); uart_send_byte(8'h23);
    uart_send_byte(8'h45); uart_send_byte(8'h67);
    uart_send_byte(8'h89); uart_send_byte(8'hab);
    uart_send_byte(8'hcd); uart_send_byte(8'hef);
    uart_send_byte(8'hfe); uart_send_byte(8'hdc);
    uart_send_byte(8'hba); uart_send_byte(8'h98);
    uart_send_byte(8'h76); uart_send_byte(8'h54);
    uart_send_byte(8'h32); uart_send_byte(8'h10);

    $display("Waiting for ciphertext...");
end

// Receive 16 bytes from tx
initial begin
    // Wait until DUT is out of reset
    @(posedge busy);

    for (k = 0; k < 16; k = k + 1) begin
        uart_recv_byte(rx_byte[k]);
    end

    $display("Received ciphertext:");
    $write("  ");
    for (k = 0; k < 16; k = k + 1)
        $write("%02x ", rx_byte[k]);
    $display("");
    $display("Expected:          68 1e df 34 d2 06 96 5e 86 b3 e9 4f 53 6e 42 46");

    if ({rx_byte[0],rx_byte[1],rx_byte[2],rx_byte[3],
         rx_byte[4],rx_byte[5],rx_byte[6],rx_byte[7],
         rx_byte[8],rx_byte[9],rx_byte[10],rx_byte[11],
         rx_byte[12],rx_byte[13],rx_byte[14],rx_byte[15]}
        == 128'h681EDF34D206965E86B3E94F536E4246)
        $display("PASS: ciphertext matches GB/T 32907-2016 vector!");
    else
        $display("FAIL: ciphertext mismatch!");

    #100000;
    $finish;
end

endmodule
