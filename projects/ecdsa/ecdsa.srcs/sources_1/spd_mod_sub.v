`timescale 1ns / 1ps
// Module: spd_mod_sub
// Description: Modular reduction mod NIST P-256.
//              Uses sequential restoring division (512 cycles).
//              Guaranteed correct. Can be replaced with fast reduction later.

module spd_mod_sub(
    input           clk,
    input           rst_n,
    input           mod_vld_i,
    input [511:0]   p512_a,
    output          mod_fin_o,
    output reg [255:0] p256_b
);

localparam [255:0] P256 = 256'hFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;

reg [511:0] dvd;
reg [256:0] partial;
reg [9:0]   cnt;
reg         active;
reg         done_r;

// Edge detection
reg  mod_vld_r1;
wire start = mod_vld_i && ~mod_vld_r1;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) mod_vld_r1 <= 0;
    else        mod_vld_r1 <= mod_vld_i;
end

// Restoring division: one bit per cycle
wire [256:0] shifted = {partial[255:0], dvd[511]};
wire [256:0] sub_val = shifted - {1'b0, P256};
wire         fits    = ~sub_val[256];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active <= 0; done_r <= 0; p256_b <= 0;
        partial <= 0; dvd <= 0; cnt <= 0;
    end else begin
        done_r <= 0;

        if (start && !active) begin
            dvd     <= p512_a;
            partial <= 257'd0;
            cnt     <= 10'd0;
            active  <= 1;
        end else if (active) begin
            partial <= fits ? sub_val : shifted;
            dvd     <= {dvd[510:0], 1'b0};

            if (cnt == 10'd511) begin
                active <= 0;
                done_r <= 1;
                p256_b <= fits ? sub_val[255:0] : shifted[255:0];
            end
            cnt <= cnt + 10'd1;
        end
    end
end

assign mod_fin_o = done_r;

endmodule
