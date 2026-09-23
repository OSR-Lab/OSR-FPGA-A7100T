`timescale 1ns / 1ps
// Module: sm4_core
// Description: SM4-128 iterative encryption core for side-channel analysis.
//              Uses a single round combinational block cycled 32 times.
//              Interface matches aes128 module in aes_A100t project.
// Dependencies: key_expansion.v, one_round_for_encdec.v

module sm4_core (
    input  wire         clk,
    input  wire         reset_n,
    input  wire         key_exp,      // Pulse: trigger key expansion
    input  wire         start,        // Pulse: trigger encryption
    input  wire [127:0] key_in,       // 128-bit user key
    input  wire [127:0] text_in,      // 128-bit plaintext
    output reg  [127:0] text_out,     // 128-bit ciphertext
    output wire         key_val,      // Key expansion done (level)
    output wire         text_val,     // Encryption done (level)
    output wire         busy          // Busy (level)
);

// -------------------------------------------------------------------
// Round key storage (32 x 32-bit round keys from key_expansion)
// -------------------------------------------------------------------
wire [31:0] rk [0:31];

// -------------------------------------------------------------------
// Key expansion (iterative, ~32 cycles, from raymondrc)
// -------------------------------------------------------------------
reg  key_exp_reg;           // Rising edge detect
wire key_exp_rise = key_exp & ~key_exp_reg;

reg  key_exp_req;
reg  user_key_valid;
reg  key_exp_req_r;         // key_exp_req delayed one cycle
wire key_exp_finished;

// Reason: key_expansion requires enable_key_exp_in already high when
// user_key_valid_in rises. So assert key_exp_req one cycle before
// user_key_valid to guarantee the IDLE->KEY_EXPANSION transition fires.
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        key_exp_reg    <= 1'b0;
        key_exp_req    <= 1'b0;
        key_exp_req_r  <= 1'b0;
        user_key_valid <= 1'b0;
    end else begin
        key_exp_reg   <= key_exp;
        key_exp_req_r <= key_exp_req;
        if (key_exp_rise) begin
            key_exp_req    <= 1'b1;
            user_key_valid <= 1'b0;   // Delay valid by one cycle
        end else begin
            // Assert user_key_valid one cycle after key_exp_req rises
            user_key_valid <= key_exp_req & ~key_exp_req_r;
            if (key_exp_finished)
                key_exp_req <= 1'b0;
        end
    end
end

key_expansion u_key_exp (
    .clk                 (clk),
    .reset_n             (reset_n),
    .sm4_enable_in       (1'b1),
    .encdec_sel_in       (1'b0),         // 0 = encryption order
    .enable_key_exp_in   (key_exp_req),
    .user_key_in         (key_in),
    .user_key_valid_in   (user_key_valid),
    .key_exp_finished_out(key_exp_finished),
    .rk00_out(rk[0]),  .rk01_out(rk[1]),  .rk02_out(rk[2]),  .rk03_out(rk[3]),
    .rk04_out(rk[4]),  .rk05_out(rk[5]),  .rk06_out(rk[6]),  .rk07_out(rk[7]),
    .rk08_out(rk[8]),  .rk09_out(rk[9]),  .rk10_out(rk[10]), .rk11_out(rk[11]),
    .rk12_out(rk[12]), .rk13_out(rk[13]), .rk14_out(rk[14]), .rk15_out(rk[15]),
    .rk16_out(rk[16]), .rk17_out(rk[17]), .rk18_out(rk[18]), .rk19_out(rk[19]),
    .rk20_out(rk[20]), .rk21_out(rk[21]), .rk22_out(rk[22]), .rk23_out(rk[23]),
    .rk24_out(rk[24]), .rk25_out(rk[25]), .rk26_out(rk[26]), .rk27_out(rk[27]),
    .rk28_out(rk[28]), .rk29_out(rk[29]), .rk30_out(rk[30]), .rk31_out(rk[31])
);

assign key_val = key_exp_finished;

// -------------------------------------------------------------------
// Iterative encryption: one round combinational logic, cycled 32 times
// -------------------------------------------------------------------
reg  [4:0]   round_cnt;     // 0..31
reg  [127:0] state;         // Current 4-word state X[i..i+3]
wire [127:0] next_state;    // Combinational output of one round

// Mux round key from stored array based on current round counter
reg  [31:0] cur_rk;
always @(*) begin
    case (round_cnt)
        5'd0:  cur_rk = rk[0];   5'd1:  cur_rk = rk[1];
        5'd2:  cur_rk = rk[2];   5'd3:  cur_rk = rk[3];
        5'd4:  cur_rk = rk[4];   5'd5:  cur_rk = rk[5];
        5'd6:  cur_rk = rk[6];   5'd7:  cur_rk = rk[7];
        5'd8:  cur_rk = rk[8];   5'd9:  cur_rk = rk[9];
        5'd10: cur_rk = rk[10];  5'd11: cur_rk = rk[11];
        5'd12: cur_rk = rk[12];  5'd13: cur_rk = rk[13];
        5'd14: cur_rk = rk[14];  5'd15: cur_rk = rk[15];
        5'd16: cur_rk = rk[16];  5'd17: cur_rk = rk[17];
        5'd18: cur_rk = rk[18];  5'd19: cur_rk = rk[19];
        5'd20: cur_rk = rk[20];  5'd21: cur_rk = rk[21];
        5'd22: cur_rk = rk[22];  5'd23: cur_rk = rk[23];
        5'd24: cur_rk = rk[24];  5'd25: cur_rk = rk[25];
        5'd26: cur_rk = rk[26];  5'd27: cur_rk = rk[27];
        5'd28: cur_rk = rk[28];  5'd29: cur_rk = rk[29];
        5'd30: cur_rk = rk[30];  default: cur_rk = rk[31];
    endcase
end

// Single round combinational block (reused for all 32 rounds)
one_round_for_encdec u_round (
    .data_in     (state),
    .round_key_in(cur_rk),
    .result_out  (next_state)
);

// FSM
localparam S_IDLE = 2'd0;
localparam S_ENC  = 2'd1;
localparam S_DONE = 2'd2;

reg [1:0] enc_state;
reg       enc_done;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        enc_state <= S_IDLE;
        round_cnt <= 5'd0;
        state     <= 128'd0;
        text_out  <= 128'd0;
        enc_done  <= 1'b0;
    end else begin
        enc_done <= 1'b0;
        case (enc_state)
            S_IDLE: begin
                if (start) begin
                    // Reason: SM4 input is X0||X1||X2||X3, direct mapping
                    state     <= text_in;
                    round_cnt <= 5'd0;
                    enc_state <= S_ENC;
                end
            end
            S_ENC: begin
                state <= next_state;
                if (round_cnt == 5'd31) begin
                    enc_state <= S_DONE;
                end else begin
                    round_cnt <= round_cnt + 1'b1;
                end
            end
            S_DONE: begin
                // Reason: SM4 final output reverses word order: Y = (X35||X34||X33||X32)
                text_out  <= { state[31:0], state[63:32],
                               state[95:64], state[127:96] };
                enc_done  <= 1'b1;
                enc_state <= S_IDLE;
            end
            default: enc_state <= S_IDLE;
        endcase
    end
end

assign text_val = enc_done;
assign busy     = (enc_state != S_IDLE) | key_exp_req;

endmodule
