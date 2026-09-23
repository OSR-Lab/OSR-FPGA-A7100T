`timescale 1ns / 1ps
// Module: mod_n_reduce
// Description: Sequential 512-bit modular reduction by SM2 curve order n.
//              Uses restoring division algorithm: 512 cycles.
//              Input: 512-bit dividend (product of two 256-bit numbers)
//              Output: 256-bit remainder = dividend mod n

module mod_n_reduce (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [511:0] dividend,
    output reg         done,
    output reg  [255:0] remainder
);

// SM2 curve order n
localparam [255:0] N256 = 256'hFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123;

reg [511:0] dvd;        // shifting dividend
reg [256:0] partial;    // partial remainder (257-bit for comparison)
reg [9:0]   cnt;
reg         active;

// Reason: One step of restoring division per clock cycle.
// shifted = (partial << 1) | dvd[511], then conditionally subtract N.
wire [256:0] shifted = {partial[255:0], dvd[511]};
wire [256:0] sub_val = shifted - {1'b0, N256};
wire         fits    = ~sub_val[256];  // shifted >= N256

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active    <= 1'b0;
        done      <= 1'b0;
        remainder <= 256'd0;
        partial   <= 257'd0;
        dvd       <= 512'd0;
        cnt       <= 10'd0;
    end else if (start && !active) begin
        dvd     <= dividend;
        partial <= 257'd0;
        cnt     <= 10'd0;
        active  <= 1'b1;
        done    <= 1'b0;
    end else if (active) begin
        partial <= fits ? sub_val : shifted;
        dvd     <= {dvd[510:0], 1'b0};

        if (cnt == 10'd511) begin
            active    <= 1'b0;
            done      <= 1'b1;
            remainder <= fits ? sub_val[255:0] : shifted[255:0];
        end
        cnt <= cnt + 10'd1;
    end else begin
        done <= 1'b0;
    end
end

endmodule
