`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module name: tb_forloop
// Description: simulation testbench for the forloop top module
//   Simulates the host sending a loop count over UART and checks that the FPGA returns the correct counter value.
//
// Test flow:
//   1. Reset the system
//   2. Send 1 byte over UART (the loop count)
//   3. Wait for the FPGA to run the for loop
//   4. Receive the 1 byte returned by the FPGA (final counter value)
//   5. Check that the returned value == the sent value
//
// UART settings: 115200 baud, 8N1, 50MHz system clock
//   bit period = 50_000_000 / 115200 = 434 clock cycles = 8680 ns
//////////////////////////////////////////////////////////////////////////////////
module tb_forloop;

// ========== Parameter definitions ==========
localparam CLK_PERIOD = 20;           // 50MHz -> 20ns period
localparam BIT_PERIOD = 8680;         // 115200 baud -> 8680 ns/bit

// ========== Signal declarations ==========
reg         clk;
reg         rst;
wire        tx;
reg         rx;
wire        busy;
wire        rx_led;
wire        loop_led;
wire        tx_led;
wire        trigger;

// ========== Device under test instance ==========
forloop uut (
    .clk_50m_ext    (clk),
    .tx             (tx),
    .rx             (rx),
    .rst            (rst),
    .busy           (busy),
    .rx_led         (rx_led),
    .loop_led       (loop_led),
    .tx_led         (tx_led),
    .trigger        (trigger)
);

// ========== Clock generation ==========
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ========== UART transmit task ==========
// simulate the host sending one byte to the FPGA (8N1 format)
task uart_send_byte;
    input [7:0] data;
    integer i;
    begin
        // start bit (low)
        rx = 1'b0;
        #BIT_PERIOD;
        // data bits D0~D7 (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i];
            #BIT_PERIOD;
        end
        // stop bit (high)
        rx = 1'b1;
        #BIT_PERIOD;
    end
endtask

// ========== UART receive task ==========
// receive one byte from the FPGA (sampled on the tx pin)
reg [7:0] received_byte;
task uart_recv_byte;
    integer i;
    begin
        // wait for the start bit (falling edge on tx)
        @(negedge tx);
        // wait half a bit period to reach the bit midpoint
        #(BIT_PERIOD / 2);
        // skip the rest of the start bit
        #BIT_PERIOD;
        // sample the 8 data bits
        for (i = 0; i < 8; i = i + 1) begin
            received_byte[i] = tx;
            #BIT_PERIOD;
        end
    end
endtask

// ========== Main test sequence ==========
reg [7:0] test_val;
initial begin
    // initialise
    rx  = 1'b1;    // the UART idle level is high
    rst = 1'b0;    // assert reset

    // release reset
    #500;
    rst = 1'b1;
    #500;

    // ---- Test 1: send N=10 ----
    test_val = 8'd10;
    $display("[%0t] TEST 1: Sending loop count = %0d", $time, test_val);
    uart_send_byte(test_val);

    // receive the returned value
    uart_recv_byte;
    $display("[%0t] TEST 1: Received = %0d, Expected = %0d", $time, received_byte, test_val);
    if (received_byte == test_val)
        $display("[%0t] TEST 1: PASS", $time);
    else
        $display("[%0t] TEST 1: FAIL!", $time);

    #(BIT_PERIOD * 2);

    // ---- Test 2: send N=0 (boundary case) ----
    test_val = 8'd0;
    $display("[%0t] TEST 2: Sending loop count = %0d", $time, test_val);
    uart_send_byte(test_val);

    uart_recv_byte;
    $display("[%0t] TEST 2: Received = %0d, Expected = %0d", $time, received_byte, test_val);
    if (received_byte == test_val)
        $display("[%0t] TEST 2: PASS", $time);
    else
        $display("[%0t] TEST 2: FAIL!", $time);

    #(BIT_PERIOD * 2);

    // ---- Test 3: send N=255 (maximum value) ----
    test_val = 8'd255;
    $display("[%0t] TEST 3: Sending loop count = %0d", $time, test_val);
    uart_send_byte(test_val);

    uart_recv_byte;
    $display("[%0t] TEST 3: Received = %0d, Expected = %0d", $time, received_byte, test_val);
    if (received_byte == test_val)
        $display("[%0t] TEST 3: PASS", $time);
    else
        $display("[%0t] TEST 3: FAIL!", $time);

    #(BIT_PERIOD * 2);

    $display("[%0t] All tests completed.", $time);
    $finish;
end

endmodule
