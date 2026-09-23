`timescale 1ns / 1ps

// Testbench for hmac_sha256_recv
// Sends 32 bytes (16B key + 16B msg) via UART, receives 32 bytes HMAC digest,
// compares against Python-computed reference.
//
// Test vector:
//   Key:  000102030405060708090a0b0c0d0e0f
//   Msg:  00112233445566778899aabbccddeeff
//   HMAC: 32cd28477b88c12e515b0e1fd7330d19616a4a51f6c502d64fe6a93fe7f786fa

module hmac_sha256_tb;

// 50 MHz clock -> 20ns period
localparam CLK_PERIOD = 20;
// 115200 baud bit period: 50_000_000 / 115200 = 434 cycles * 20ns = 8680ns
localparam BIT_PERIOD = 8680;

reg  clk;
wire tx;
reg  rx;
wire busy;

hmac_sha256_recv DUT (
    .clk_50m_ext (clk),
    .tx          (tx),
    .rx          (rx),
    .busy        (busy)
);

// Clock generation
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// Test data
reg [7:0] tx_data [0:31];  // 32 bytes to send (key + msg)
reg [7:0] rx_data [0:31];  // 32 bytes received (HMAC)
reg [255:0] expected_hmac;
reg [255:0] received_hmac;

// UART send task: 8N1, LSB first
task uart_send_byte;
    input [7:0] data;
    integer j;
    begin
        // Start bit
        rx = 1'b0;
        #(BIT_PERIOD);
        // 8 data bits (LSB first)
        for (j = 0; j < 8; j = j + 1) begin
            rx = data[j];
            #(BIT_PERIOD);
        end
        // Stop bit
        rx = 1'b1;
        #(BIT_PERIOD);
    end
endtask

// UART receive task: 8N1, LSB first
task uart_recv_byte;
    output [7:0] data;
    integer j;
    begin
        // Wait for start bit (tx goes low)
        @(negedge tx);
        // Wait to middle of start bit
        #(BIT_PERIOD / 2);
        // Sample 8 data bits at midpoint
        for (j = 0; j < 8; j = j + 1) begin
            #(BIT_PERIOD);
            data[j] = tx;
        end
        // Wait for stop bit
        #(BIT_PERIOD);
    end
endtask

integer i;
integer ri;
integer errors;

initial begin
    // Initialize
    rx = 1'b1;  // UART idle = high
    errors = 0;

    // Key: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
    for (i = 0; i < 16; i = i + 1)
        tx_data[i] = i[7:0];

    // Msg: 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff
    tx_data[16] = 8'h00; tx_data[17] = 8'h11;
    tx_data[18] = 8'h22; tx_data[19] = 8'h33;
    tx_data[20] = 8'h44; tx_data[21] = 8'h55;
    tx_data[22] = 8'h66; tx_data[23] = 8'h77;
    tx_data[24] = 8'h88; tx_data[25] = 8'h99;
    tx_data[26] = 8'haa; tx_data[27] = 8'hbb;
    tx_data[28] = 8'hcc; tx_data[29] = 8'hdd;
    tx_data[30] = 8'hee; tx_data[31] = 8'hff;

    expected_hmac = 256'h32cd28477b88c12e515b0e1fd7330d19616a4a51f6c502d64fe6a93fe7f786fa;

    // Wait for DUT reset to complete (rst_cnt reaches 8)
    #(CLK_PERIOD * 20);

    $display("=== HMAC-SHA256 Testbench ===");
    $display("Key: 000102030405060708090a0b0c0d0e0f");
    $display("Msg: 00112233445566778899aabbccddeeff");

    // Send and receive concurrently: the DUT starts transmitting the HMAC
    // result as soon as computation finishes, which can happen before the
    // testbench finishes sending the last input byte. Using fork/join
    // ensures the receive process is listening from the start.
    fork
        begin
            $display("[%0t] Sending 32 bytes via UART...", $time);
            for (i = 0; i < 32; i = i + 1) begin
                uart_send_byte(tx_data[i]);
            end
            $display("[%0t] All 32 bytes sent. Waiting for HMAC computation and response...", $time);
        end
        begin
            for (ri = 0; ri < 32; ri = ri + 1) begin
                uart_recv_byte(rx_data[ri]);
            end
        end
    join

    // Assemble received HMAC (MSB first)
    received_hmac = 256'b0;
    for (i = 0; i < 32; i = i + 1) begin
        received_hmac = {received_hmac[247:0], rx_data[i]};
    end

    $display("");
    $display("Expected HMAC: %064h", expected_hmac);
    $display("Received HMAC: %064h", received_hmac);

    if (received_hmac === expected_hmac) begin
        $display("*** PASS ***");
    end else begin
        $display("*** FAIL ***");
        // Show byte-by-byte diff
        for (i = 0; i < 32; i = i + 1) begin
            if (rx_data[i] !== expected_hmac[255 - i*8 -: 8])
                $display("  Byte %0d: expected %02h, got %02h",
                         i, expected_hmac[255 - i*8 -: 8], rx_data[i]);
        end
    end

    #(BIT_PERIOD * 2);
    $finish;
end

// Timeout watchdog
initial begin
    #200_000_000;
    $display("*** TIMEOUT ***");
    $finish;
end

endmodule
