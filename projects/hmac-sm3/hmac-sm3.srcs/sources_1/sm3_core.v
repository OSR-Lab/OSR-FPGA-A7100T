//======================================================================
//
// sm3_core.v
// ----------
// Verilog 2001 implementation of the SM3 hash function.
// Block-level interface matching sha256_core (secworks) for
// drop-in use with the same HMAC wrapper pattern.
//
// Interface:
//   init  - Start new hash (load IV).
//   next  - Process next block (chain from previous digest).
//   block - 512-bit message block input.
//   ready - HIGH when core can accept a new block.
//   digest      - 256-bit hash output.
//   digest_valid - HIGH when digest is valid.
//
// SM3 differences from SHA-256:
//   - Digest update uses XOR (not addition).
//   - Different round function (SS1, SS2, TT1, TT2, P0).
//   - Round constant TJ is rotated by (j mod 32) each round.
//   - State update: C=B<<<9, G=F<<<19, E=P0(TT2).
//
//======================================================================

`default_nettype none

module sm3_core(
                input wire            clk,
                input wire            reset_n,

                input wire            init,
                input wire            next,

                input wire [511 : 0]  block,

                output wire           ready,
                output wire [255 : 0] digest,
                output wire           digest_valid
               );


  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam SM3_H0_0 = 32'h7380166f;
  localparam SM3_H0_1 = 32'h4914b2b9;
  localparam SM3_H0_2 = 32'h172442d7;
  localparam SM3_H0_3 = 32'hda8a0600;
  localparam SM3_H0_4 = 32'ha96f30bc;
  localparam SM3_H0_5 = 32'h163138aa;
  localparam SM3_H0_6 = 32'he38dee4d;
  localparam SM3_H0_7 = 32'hb0fb0e4e;

  localparam SM3_ROUNDS = 63;

  localparam CTRL_IDLE   = 0;
  localparam CTRL_ROUNDS = 1;
  localparam CTRL_DONE   = 2;


  //----------------------------------------------------------------
  // Registers including update variables and write enable.
  //----------------------------------------------------------------
  reg [31 : 0] a_reg;
  reg [31 : 0] a_new;
  reg [31 : 0] b_reg;
  reg [31 : 0] b_new;
  reg [31 : 0] c_reg;
  reg [31 : 0] c_new;
  reg [31 : 0] d_reg;
  reg [31 : 0] d_new;
  reg [31 : 0] e_reg;
  reg [31 : 0] e_new;
  reg [31 : 0] f_reg;
  reg [31 : 0] f_new;
  reg [31 : 0] g_reg;
  reg [31 : 0] g_new;
  reg [31 : 0] h_reg;
  reg [31 : 0] h_new;
  reg          a_h_we;

  reg [31 : 0] H0_reg;
  reg [31 : 0] H0_new;
  reg [31 : 0] H1_reg;
  reg [31 : 0] H1_new;
  reg [31 : 0] H2_reg;
  reg [31 : 0] H2_new;
  reg [31 : 0] H3_reg;
  reg [31 : 0] H3_new;
  reg [31 : 0] H4_reg;
  reg [31 : 0] H4_new;
  reg [31 : 0] H5_reg;
  reg [31 : 0] H5_new;
  reg [31 : 0] H6_reg;
  reg [31 : 0] H6_new;
  reg [31 : 0] H7_reg;
  reg [31 : 0] H7_new;
  reg          H_we;

  reg [5 : 0] t_ctr_reg;
  reg [5 : 0] t_ctr_new;
  reg         t_ctr_we;
  reg         t_ctr_inc;
  reg         t_ctr_rst;

  reg digest_valid_reg;
  reg digest_valid_new;
  reg digest_valid_we;

  reg [1 : 0] sm3_ctrl_reg;
  reg [1 : 0] sm3_ctrl_new;
  reg         sm3_ctrl_we;


  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg digest_init;
  reg digest_update;

  reg state_init;
  reg state_update;

  reg first_block;

  reg ready_flag;

  reg [31 : 0] tt1;
  reg [31 : 0] tt2_p0;

  reg           w_init;
  reg           w_next;
  wire [31 : 0] w_data;
  wire [31 : 0] w_p_data;

  // TJ constant and rotation
  wire [31 : 0] tj;
  wire [31 : 0] tj_rotated;
  wire [4 : 0]  j_mod;


  //----------------------------------------------------------------
  // Module instantiations.
  //----------------------------------------------------------------
  sm3_w_mem w_mem_inst(
                       .clk(clk),
                       .reset_n(reset_n),
                       .block(block),
                       .init(w_init),
                       .next(w_next),
                       .w(w_data),
                       .w_p(w_p_data)
                      );

  // TJ = 0x79cc4519 for j < 16, 0x7a879d8a for j >= 16
  // Rotated left by (j mod 32) positions
  assign tj    = (t_ctr_reg < 6'd16) ? 32'h79cc4519 : 32'h7a879d8a;
  assign j_mod = t_ctr_reg[4:0];

  barrel_shifter tj_rotator(
                             .data_in(tj),
                             .shift_number_in(j_mod),
                             .data_after_shift_out(tj_rotated)
                            );


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign ready = ready_flag;

  assign digest = {H0_reg, H1_reg, H2_reg, H3_reg,
                   H4_reg, H5_reg, H6_reg, H7_reg};

  assign digest_valid = digest_valid_reg;


  //----------------------------------------------------------------
  // reg_update
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin : reg_update
      if (!reset_n)
        begin
          a_reg            <= 32'h0;
          b_reg            <= 32'h0;
          c_reg            <= 32'h0;
          d_reg            <= 32'h0;
          e_reg            <= 32'h0;
          f_reg            <= 32'h0;
          g_reg            <= 32'h0;
          h_reg            <= 32'h0;
          H0_reg           <= 32'h0;
          H1_reg           <= 32'h0;
          H2_reg           <= 32'h0;
          H3_reg           <= 32'h0;
          H4_reg           <= 32'h0;
          H5_reg           <= 32'h0;
          H6_reg           <= 32'h0;
          H7_reg           <= 32'h0;
          digest_valid_reg <= 0;
          t_ctr_reg        <= 6'h0;
          sm3_ctrl_reg     <= CTRL_IDLE;
        end
      else
        begin
          if (a_h_we)
            begin
              a_reg <= a_new;
              b_reg <= b_new;
              c_reg <= c_new;
              d_reg <= d_new;
              e_reg <= e_new;
              f_reg <= f_new;
              g_reg <= g_new;
              h_reg <= h_new;
            end

          if (H_we)
            begin
              H0_reg <= H0_new;
              H1_reg <= H1_new;
              H2_reg <= H2_new;
              H3_reg <= H3_new;
              H4_reg <= H4_new;
              H5_reg <= H5_new;
              H6_reg <= H6_new;
              H7_reg <= H7_new;
            end

          if (t_ctr_we)
            t_ctr_reg <= t_ctr_new;

          if (digest_valid_we)
            digest_valid_reg <= digest_valid_new;

          if (sm3_ctrl_we)
            sm3_ctrl_reg <= sm3_ctrl_new;
        end
    end // reg_update


  //----------------------------------------------------------------
  // digest_logic
  //
  // SM3 digest update: V_{i+1} = CF(V_i, B_i) XOR V_i
  // Note: XOR, not addition (unlike SHA-256).
  //----------------------------------------------------------------
  always @*
    begin : digest_logic
      H0_new = 32'h0;
      H1_new = 32'h0;
      H2_new = 32'h0;
      H3_new = 32'h0;
      H4_new = 32'h0;
      H5_new = 32'h0;
      H6_new = 32'h0;
      H7_new = 32'h0;
      H_we = 0;

      if (digest_init)
        begin
          H_we = 1;
          H0_new = SM3_H0_0;
          H1_new = SM3_H0_1;
          H2_new = SM3_H0_2;
          H3_new = SM3_H0_3;
          H4_new = SM3_H0_4;
          H5_new = SM3_H0_5;
          H6_new = SM3_H0_6;
          H7_new = SM3_H0_7;
        end

      if (digest_update)
        begin
          H0_new = H0_reg ^ a_reg;
          H1_new = H1_reg ^ b_reg;
          H2_new = H2_reg ^ c_reg;
          H3_new = H3_reg ^ d_reg;
          H4_new = H4_reg ^ e_reg;
          H5_new = H5_reg ^ f_reg;
          H6_new = H6_reg ^ g_reg;
          H7_new = H7_reg ^ h_reg;
          H_we = 1;
        end
    end // digest_logic


  //----------------------------------------------------------------
  // sm3_round_logic
  //
  // SM3 round function:
  //   SS1 = ((A<<<12) + E + (TJ<<<j)) <<< 7
  //   SS2 = SS1 ^ (A<<<12)
  //   TT1 = FF(A,B,C) + D + SS2 + W'_j
  //   TT2 = GG(E,F,G) + H + SS1 + W_j
  //
  //   FF = A^B^C (j<16),  (A&B)|(A&C)|(B&C) (j>=16)
  //   GG = E^F^G (j<16),  (E&F)|(~E&G)      (j>=16)
  //----------------------------------------------------------------
  always @*
    begin : sm3_round_logic
      reg [31 : 0] a_rot12;
      reg [31 : 0] ss1_pre;
      reg [31 : 0] ss1;
      reg [31 : 0] ss2;
      reg [31 : 0] ff_val;
      reg [31 : 0] gg_val;
      reg [31 : 0] tt2_raw;

      // A<<<12
      a_rot12 = {a_reg[19:0], a_reg[31:20]};

      // SS1 = ((A<<<12) + E + (TJ<<<j)) <<< 7
      ss1_pre = a_rot12 + e_reg + tj_rotated;
      ss1     = {ss1_pre[24:0], ss1_pre[31:25]};

      // SS2 = SS1 ^ (A<<<12)
      ss2 = ss1 ^ a_rot12;

      // FF and GG depend on round number
      if (t_ctr_reg < 6'd16)
        begin
          ff_val = a_reg ^ b_reg ^ c_reg;
          gg_val = e_reg ^ f_reg ^ g_reg;
        end
      else
        begin
          ff_val = (a_reg & b_reg) | (a_reg & c_reg) | (b_reg & c_reg);
          gg_val = (e_reg & f_reg) | (~e_reg & g_reg);
        end

      // TT1 = FF(A,B,C) + D + SS2 + W'_j
      tt1 = ff_val + d_reg + ss2 + w_p_data;

      // TT2 = GG(E,F,G) + H + SS1 + W_j
      tt2_raw = gg_val + h_reg + ss1 + w_data;

      // P0(TT2) = TT2 ^ (TT2<<<9) ^ (TT2<<<17)
      tt2_p0 = tt2_raw ^ {tt2_raw[22:0], tt2_raw[31:23]}
                        ^ {tt2_raw[14:0], tt2_raw[31:15]};
    end // sm3_round_logic


  //----------------------------------------------------------------
  // state_logic
  //
  // State update for SM3:
  //   D=C, C=B<<<9, B=A, A=TT1
  //   H=G, G=F<<<19, F=E, E=P0(TT2)
  //----------------------------------------------------------------
  always @*
    begin : state_logic
      a_new  = 32'h0;
      b_new  = 32'h0;
      c_new  = 32'h0;
      d_new  = 32'h0;
      e_new  = 32'h0;
      f_new  = 32'h0;
      g_new  = 32'h0;
      h_new  = 32'h0;
      a_h_we = 0;

      if (state_init)
        begin
          a_h_we = 1;
          if (first_block)
            begin
              a_new = SM3_H0_0;
              b_new = SM3_H0_1;
              c_new = SM3_H0_2;
              d_new = SM3_H0_3;
              e_new = SM3_H0_4;
              f_new = SM3_H0_5;
              g_new = SM3_H0_6;
              h_new = SM3_H0_7;
            end
          else
            begin
              a_new = H0_reg;
              b_new = H1_reg;
              c_new = H2_reg;
              d_new = H3_reg;
              e_new = H4_reg;
              f_new = H5_reg;
              g_new = H6_reg;
              h_new = H7_reg;
            end
        end

      if (state_update)
        begin
          a_new  = tt1;
          b_new  = a_reg;
          c_new  = {b_reg[22:0], b_reg[31:23]};  // B<<<9
          d_new  = c_reg;
          e_new  = tt2_p0;
          f_new  = e_reg;
          g_new  = {f_reg[12:0], f_reg[31:13]};  // F<<<19
          h_new  = g_reg;
          a_h_we = 1;
        end
    end // state_logic


  //----------------------------------------------------------------
  // t_ctr
  //----------------------------------------------------------------
  always @*
    begin : t_ctr
      t_ctr_new = 0;
      t_ctr_we  = 0;

      if (t_ctr_rst)
        begin
          t_ctr_new = 0;
          t_ctr_we  = 1;
        end

      if (t_ctr_inc)
        begin
          t_ctr_new = t_ctr_reg + 1'b1;
          t_ctr_we  = 1;
        end
    end // t_ctr


  //----------------------------------------------------------------
  // sm3_ctrl_fsm
  //
  // Logic for the state machine controlling the core behaviour.
  // Identical structure to sha256_core.
  //----------------------------------------------------------------
  always @*
    begin : sm3_ctrl_fsm
      digest_init      = 0;
      digest_update    = 0;

      state_init       = 0;
      state_update     = 0;

      first_block      = 0;
      ready_flag       = 0;

      w_init           = 0;
      w_next           = 0;

      t_ctr_inc        = 0;
      t_ctr_rst        = 0;

      digest_valid_new = 0;
      digest_valid_we  = 0;

      sm3_ctrl_new     = CTRL_IDLE;
      sm3_ctrl_we      = 0;


      case (sm3_ctrl_reg)
        CTRL_IDLE:
          begin
            ready_flag = 1;

            if (init)
              begin
                digest_init      = 1;
                w_init           = 1;
                state_init       = 1;
                first_block      = 1;
                t_ctr_rst        = 1;
                digest_valid_new = 0;
                digest_valid_we  = 1;
                sm3_ctrl_new     = CTRL_ROUNDS;
                sm3_ctrl_we      = 1;
              end

            if (next)
              begin
                t_ctr_rst        = 1;
                w_init           = 1;
                state_init       = 1;
                digest_valid_new = 0;
                digest_valid_we  = 1;
                sm3_ctrl_new     = CTRL_ROUNDS;
                sm3_ctrl_we      = 1;
              end
          end


        CTRL_ROUNDS:
          begin
            w_next       = 1;
            state_update = 1;
            t_ctr_inc    = 1;

            if (t_ctr_reg == SM3_ROUNDS)
              begin
                sm3_ctrl_new = CTRL_DONE;
                sm3_ctrl_we  = 1;
              end
          end


        CTRL_DONE:
          begin
            digest_update    = 1;
            digest_valid_new = 1;
            digest_valid_we  = 1;

            sm3_ctrl_new     = CTRL_IDLE;
            sm3_ctrl_we      = 1;
          end
      endcase // case (sm3_ctrl_reg)
    end // sm3_ctrl_fsm

endmodule // sm3_core

`default_nettype wire

//======================================================================
// EOF sm3_core.v
//======================================================================
