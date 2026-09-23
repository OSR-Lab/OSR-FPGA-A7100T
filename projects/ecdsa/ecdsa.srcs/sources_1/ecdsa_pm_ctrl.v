`timescale 1ns / 1ps
// Module: sm2_pm_ctrl
// Description: SM2 scalar point multiplication controller.
//              Implements Double-and-Add algorithm: result = k * P
//              where P = (base_x_i, base_y_i) is an arbitrary base point.
//              Before the double-and-add loop, sends UPDT_REG instructions
//              to point_cal_top to set P0 and P1 to the base point.
//
//              Interface:
//                start_i            : pulse to begin computation
//                k_i                : 256-bit scalar
//                base_x_i, base_y_i : affine base point coordinates
//                done_o             : pulse when Jacobian result is ready
//                xj_o/yj_o/zj_o    : Jacobian result coordinates

module ecdsa_pm_ctrl (
    input           clk,
    input           rst_n,

    // Control interface
    input           start_i,
    input  [255:0]  k_i,
    input  [255:0]  base_x_i,
    input  [255:0]  base_y_i,

    // Result (Jacobian coordinates)
    output [255:0]  xj_o,
    output [255:0]  yj_o,
    output [255:0]  zj_o,
    output          done_o
);

// ---------------------------------------------------------------------------
// Instruction encoding constants (match point_cal_top)
// ---------------------------------------------------------------------------
localparam OP_X2  = 4'd0,  OP_Y2  = 4'd1,  OP_Z2  = 4'd2;
localparam OP_T0  = 4'd3,  OP_T1  = 4'd4,  OP_T2  = 4'd5;
localparam OP_X0  = 4'd6,  OP_Y0  = 4'd7,  OP_Z0  = 4'd8;
localparam OP_X1  = 4'd9,  OP_Y1  = 4'd10, OP_Z1  = 4'd11;
localparam OP_NULL= 4'd15;

localparam OP_MUL = 2'b00;
localparam OP_ADD = 2'b01;
localparam OP_SUB = 2'b10;
localparam OP_NUL = 2'b11;

localparam INS_CAL      = 2'b00;
localparam INS_UPDT_REG = 2'b01;
localparam INS_FIN      = 2'b10;
localparam INS_NULL     = 2'b11;

// ---------------------------------------------------------------------------
// Point Doubling instruction list (12 rounds x 3 instructions each)
// ---------------------------------------------------------------------------
localparam PD_RNDS = 12;
wire [16*3*PD_RNDS-1:0] ins_lst_pd = {
    // rnd 0
    {OP_MUL,INS_CAL,OP_Z0,OP_Z0,OP_T2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 1
    {OP_SUB,INS_CAL,OP_X0,OP_T2,OP_X2},
    {OP_ADD,INS_CAL,OP_X0,OP_T2,OP_Y2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 2
    {OP_MUL,INS_CAL,OP_X2,OP_Y2,OP_Y2},
    {OP_MUL,INS_CAL,OP_Y0,OP_Y0,OP_T0},
    {OP_MUL,INS_CAL,OP_Y0,OP_Z0,OP_Z2},
    // rnd 3
    {OP_ADD,INS_CAL,OP_T0,OP_T0,OP_T0},
    {OP_ADD,INS_CAL,OP_Y2,OP_Y2,OP_T2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 4
    {OP_ADD,INS_CAL,OP_Z2,OP_Z2,OP_Z2},
    {OP_ADD,INS_CAL,OP_Y2,OP_T2,OP_Y2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 5
    {OP_MUL,INS_CAL,OP_Y2,OP_Y2,OP_T2},
    {OP_MUL,INS_CAL,OP_X0,OP_T0,OP_T0},
    {OP_MUL,INS_CAL,OP_T0,OP_T0,OP_T1},
    // rnd 6
    {OP_ADD,INS_CAL,OP_T0,OP_T0,OP_T0},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 7
    {OP_ADD,INS_CAL,OP_T0,OP_T0,OP_X2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 8
    {OP_SUB,INS_CAL,OP_T2,OP_X2,OP_X2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 9
    {OP_ADD,INS_CAL,OP_T1,OP_T1,OP_T1},
    {OP_SUB,INS_CAL,OP_T0,OP_X2,OP_T0},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 10
    {OP_MUL,INS_CAL,OP_T0,OP_Y2,OP_Y2},
    {OP_MUL,INS_CAL,OP_Z2,OP_Z2,OP_T2},
    {OP_MUL,INS_CAL,OP_Z2,OP_Y1,OP_T0},
    // rnd 11
    {OP_SUB,INS_CAL,OP_Y2,OP_T1,OP_Y2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL}
};

// Point Addition instruction list (10 rounds x 3 instructions each)
localparam PA_RNDS = 10;
wire [16*3*PA_RNDS-1:0] ins_lst_pa = {
    // rnd 0
    {OP_MUL,INS_CAL,OP_Z0,OP_Z0,OP_T2},
    {OP_MUL,INS_CAL,OP_Z0,OP_Y1,OP_T0},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 1
    {OP_MUL,INS_CAL,OP_T2,OP_T0,OP_T1},
    {OP_MUL,INS_CAL,OP_X1,OP_T2,OP_Z2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 2
    {OP_SUB,INS_CAL,OP_Z2,OP_X0,OP_T0},
    {OP_SUB,INS_CAL,OP_T1,OP_Y0,OP_T1},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 3
    {OP_MUL,INS_CAL,OP_T0,OP_Z0,OP_Z2},
    {OP_MUL,INS_CAL,OP_T0,OP_T0,OP_T2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 4
    {OP_MUL,INS_CAL,OP_T0,OP_T2,OP_Y2},
    {OP_MUL,INS_CAL,OP_T2,OP_X0,OP_T2},
    {OP_MUL,INS_CAL,OP_T1,OP_T1,OP_X2},
    // rnd 5
    {OP_SUB,INS_CAL,OP_X2,OP_Y2,OP_X2},
    {OP_ADD,INS_CAL,OP_T2,OP_T2,OP_T0},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 6
    {OP_SUB,INS_CAL,OP_X2,OP_T0,OP_X2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 7
    {OP_SUB,INS_CAL,OP_T2,OP_X2,OP_T2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    // rnd 8
    {OP_MUL,INS_CAL,OP_T1,OP_T2,OP_T1},
    {OP_MUL,INS_CAL,OP_Y0,OP_Y2,OP_Y2},
    {OP_MUL,INS_CAL,OP_Z2,OP_Z2,OP_T2},
    // rnd 9
    {OP_SUB,INS_CAL,OP_T1,OP_Y2,OP_Y2},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL},
    {OP_NUL,INS_NULL,OP_NULL,OP_NULL,OP_NULL}
};

// ---------------------------------------------------------------------------
// point_cal_top interface signals
// ---------------------------------------------------------------------------
reg  [15:0] ins_0, ins_1, ins_2;
reg         ins_vld;
reg  [255:0] data_path_out;    // data for UPDT_REG instructions
wire [255:0] var_x2, var_y2, var_z2;
wire         intr_cal_done;

point_cal_top U_pt_cal (
    .clk            (clk),
    .rst_n          (rst_n),
    .ins_0_i        (ins_0),
    .ins_1_i        (ins_1),
    .ins_2_i        (ins_2),
    .ins_vld_i      (ins_vld),
    .data_path_i    (data_path_out),
    .var_x2_o       (var_x2),
    .var_y2_o       (var_y2),
    .var_z2_o       (var_z2),
    .intr_cal_done_o(intr_cal_done)
);

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------
localparam S_IDLE       = 4'd0;
localparam S_INIT_BASE  = 4'd1;   // Send UPDT_REG to load base point
localparam S_INIT_WAIT  = 4'd2;   // Wait for UPDT_REG to complete
localparam S_SCAN_K     = 4'd3;
localparam S_PD_START   = 4'd4;
localparam S_PD_WAIT    = 4'd5;
localparam S_PD_FIN     = 4'd6;
localparam S_PA_START   = 4'd7;
localparam S_PA_WAIT    = 4'd8;
localparam S_PA_FIN     = 4'd9;
localparam S_DONE       = 4'd10;

reg [3:0]   state;

reg [255:0] k_reg;
reg [8:0]   k_bits_left;
reg [4:0]   rnd_cnt;
reg [16*3*PD_RNDS-1:0] ins_shift_reg;
reg [4:0]   rnd_total;
reg         done_reg;
reg         first_bit;

// Base point initialization
reg [2:0]   init_idx;       // 0-5: X0,Y0,Z0,X1,Y1,Z1
reg [1:0]   init_wait_cnt;  // wait counter for UPDT_REG processing

// Reason: Register IDs for UPDT_REG, indexed by init_idx
wire [3:0] init_reg_id [0:5];
assign init_reg_id[0] = OP_X0;  // 6
assign init_reg_id[1] = OP_Y0;  // 7
assign init_reg_id[2] = OP_Z0;  // 8
assign init_reg_id[3] = OP_X1;  // 9
assign init_reg_id[4] = OP_Y1;  // 10
assign init_reg_id[5] = OP_Z1;  // 11

assign xj_o  = var_x2;
assign yj_o  = var_y2;
assign zj_o  = var_z2;
assign done_o = done_reg;

wire k_top = k_reg[255];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= S_IDLE;
        k_reg         <= 256'd0;
        k_bits_left   <= 9'd0;
        rnd_cnt       <= 5'd0;
        ins_shift_reg <= {(16*3*PD_RNDS){1'b0}};
        rnd_total     <= 5'd0;
        ins_0         <= 16'd0;
        ins_1         <= 16'd0;
        ins_2         <= 16'd0;
        ins_vld       <= 1'b0;
        done_reg      <= 1'b0;
        first_bit     <= 1'b1;
        data_path_out <= 256'd0;
        init_idx      <= 3'd0;
        init_wait_cnt <= 2'd0;
    end else begin
        ins_vld  <= 1'b0;   // Default
        done_reg <= 1'b0;

        case (state)
            // -----------------------------------------------------------
            S_IDLE: begin
                first_bit   <= 1'b1;
                rnd_cnt     <= 5'd0;
                if (start_i) begin
                    k_reg       <= k_i;
                    k_bits_left <= 9'd256;
                    init_idx    <= 3'd0;
                    init_wait_cnt <= 2'd0;
                    state       <= S_INIT_BASE;
                end
            end

            // -----------------------------------------------------------
            // Initialize base point: send 6 UPDT_REG instructions
            // (X0, Y0, Z0, X1, Y1, Z1) to point_cal_top
            S_INIT_BASE: begin
                // Set data and instruction
                case (init_idx)
                    3'd0: data_path_out <= base_x_i;
                    3'd1: data_path_out <= base_y_i;
                    3'd2: data_path_out <= 256'd1;
                    3'd3: data_path_out <= base_x_i;
                    3'd4: data_path_out <= base_y_i;
                    3'd5: data_path_out <= 256'd1;
                    default: data_path_out <= 256'd0;
                endcase
                ins_0   <= {OP_NUL, INS_UPDT_REG, 4'd0, 4'd0, init_reg_id[init_idx]};
                ins_1   <= 16'd0;
                ins_2   <= 16'd0;
                ins_vld <= 1'b1;
                init_wait_cnt <= 2'd0;
                state   <= S_INIT_WAIT;
            end

            // Wait for point_cal_top to process UPDT_REG (IDLE->UPDT_REG->IDLE = 2 cycles)
            S_INIT_WAIT: begin
                if (init_wait_cnt == 2'd2) begin
                    if (init_idx == 3'd5) begin
                        state <= S_SCAN_K;
                    end else begin
                        init_idx <= init_idx + 3'd1;
                        state    <= S_INIT_BASE;
                    end
                end else begin
                    init_wait_cnt <= init_wait_cnt + 2'd1;
                end
            end

            // -----------------------------------------------------------
            S_SCAN_K: begin
                if (k_bits_left == 9'd0) begin
                    done_reg <= 1'b1;
                    state    <= S_IDLE;
                end else if (k_reg[255]) begin
                    k_reg       <= {k_reg[254:0], 1'b0};
                    k_bits_left <= k_bits_left - 9'd1;
                    state       <= S_PD_START;
                    rnd_cnt     <= 5'd0;
                    ins_shift_reg <= ins_lst_pd;
                    rnd_total     <= PD_RNDS;
                end else begin
                    k_reg       <= {k_reg[254:0], 1'b0};
                    k_bits_left <= k_bits_left - 9'd1;
                end
            end

            // -----------------------------------------------------------
            S_PD_START: begin
                ins_0 <= ins_shift_reg[16*3*PD_RNDS-1    -: 16];
                ins_1 <= ins_shift_reg[16*3*PD_RNDS-1-16  -: 16];
                ins_2 <= ins_shift_reg[16*3*PD_RNDS-1-32  -: 16];
                ins_vld       <= 1'b1;
                ins_shift_reg <= {ins_shift_reg[16*3*PD_RNDS-49:0], 48'd0};
                state         <= S_PD_WAIT;
            end

            S_PD_WAIT: begin
                if (intr_cal_done) begin
                    rnd_cnt <= rnd_cnt + 5'd1;
                    if (rnd_cnt + 5'd1 == rnd_total) begin
                        ins_0   <= {OP_NUL, INS_FIN, 4'd0, 4'd0, 4'd0};
                        ins_1   <= 16'd0;
                        ins_2   <= 16'd0;
                        ins_vld <= 1'b1;
                        state   <= S_PD_FIN;
                    end else begin
                        state <= S_PD_START;
                    end
                end
            end

            S_PD_FIN: begin
                if (k_bits_left == 9'd0) begin
                    done_reg <= 1'b1;
                    state    <= S_IDLE;
                end else begin
                    if (k_reg[255]) begin
                        state         <= S_PA_START;
                        rnd_cnt       <= 5'd0;
                        ins_shift_reg <= {ins_lst_pa, {(16*3*(PD_RNDS-PA_RNDS)){1'b0}}};
                        rnd_total     <= PA_RNDS;
                        k_reg         <= {k_reg[254:0], 1'b0};
                        k_bits_left   <= k_bits_left - 9'd1;
                    end else begin
                        k_reg         <= {k_reg[254:0], 1'b0};
                        k_bits_left   <= k_bits_left - 9'd1;
                        // Reason: If this was the LAST remaining bit (k_bits_left==1),
                        // the PD for it has already been done. Don't start another PD!
                        // Original bug: always started a new PD, causing one extra doubling
                        // (e.g., k=2^16 gave 2^17*G instead of 2^16*G).
                        if (k_bits_left == 9'd1) begin
                            done_reg <= 1'b1;
                            state    <= S_IDLE;
                        end else begin
                            state         <= S_PD_START;
                            rnd_cnt       <= 5'd0;
                            ins_shift_reg <= ins_lst_pd;
                            rnd_total     <= PD_RNDS;
                        end
                    end
                end
            end

            // -----------------------------------------------------------
            S_PA_START: begin
                ins_0 <= ins_shift_reg[16*3*PD_RNDS-1    -: 16];
                ins_1 <= ins_shift_reg[16*3*PD_RNDS-1-16  -: 16];
                ins_2 <= ins_shift_reg[16*3*PD_RNDS-1-32  -: 16];
                ins_vld       <= 1'b1;
                ins_shift_reg <= {ins_shift_reg[16*3*PD_RNDS-49:0], 48'd0};
                state         <= S_PA_WAIT;
            end

            S_PA_WAIT: begin
                if (intr_cal_done) begin
                    rnd_cnt <= rnd_cnt + 5'd1;
                    if (rnd_cnt + 5'd1 == rnd_total) begin
                        ins_0   <= {OP_NUL, INS_FIN, 4'd0, 4'd0, 4'd0};
                        ins_1   <= 16'd0;
                        ins_2   <= 16'd0;
                        ins_vld <= 1'b1;
                        state   <= S_PA_FIN;
                    end else begin
                        state <= S_PA_START;
                    end
                end
            end

            S_PA_FIN: begin
                if (k_bits_left == 9'd0) begin
                    done_reg <= 1'b1;
                    state    <= S_IDLE;
                end else begin
                    // Reason: PA_FIN must NOT consume a bit.
                    state         <= S_PD_START;
                    rnd_cnt       <= 5'd0;
                    ins_shift_reg <= ins_lst_pd;
                    rnd_total     <= PD_RNDS;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
