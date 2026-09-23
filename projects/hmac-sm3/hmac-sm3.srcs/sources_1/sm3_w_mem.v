//======================================================================
//
// sm3_w_mem.v
// -----------
// SM3 message expansion module. Generates W_j and W'_j words
// for the compression function, one pair per round.
// Interface matches sha256_w_mem for consistency.
//
// SM3 message expansion:
//   W_0..W_15 = message block words
//   W_j = P1(W_{j-16} ^ W_{j-9} ^ (W_{j-3}<<<15)) ^ (W_{j-13}<<<7) ^ W_{j-6}
//   W'_j = W_j ^ W_{j+4}
//   P1(X) = X ^ (X<<<15) ^ (X<<<23)
//
//======================================================================

`default_nettype none

module sm3_w_mem(
                 input wire            clk,
                 input wire            reset_n,

                 input wire [511 : 0]  block,

                 input wire            init,
                 input wire            next,

                 output wire [31 : 0]  w,
                 output wire [31 : 0]  w_p
                );

  //----------------------------------------------------------------
  // Registers.
  //----------------------------------------------------------------
  reg [31 : 0] w0_reg,  w1_reg,  w2_reg,  w3_reg;
  reg [31 : 0] w4_reg,  w5_reg,  w6_reg,  w7_reg;
  reg [31 : 0] w8_reg,  w9_reg,  w10_reg, w11_reg;
  reg [31 : 0] w12_reg, w13_reg, w14_reg, w15_reg;


  //----------------------------------------------------------------
  // Wires for message expansion.
  //----------------------------------------------------------------
  // W_{j-3}<<<15  (w13 in shifted position maps to w_{j-3})
  wire [31 : 0] w13_rot15;
  assign w13_rot15 = {w13_reg[16:0], w13_reg[31:17]};

  // W_{j-13}<<<7  (w3 maps to w_{j-13})
  wire [31 : 0] w3_rot7;
  assign w3_rot7 = {w3_reg[24:0], w3_reg[31:25]};

  // P1 input: W_{j-16} ^ W_{j-9} ^ (W_{j-3}<<<15)
  wire [31 : 0] p1_in;
  assign p1_in = w0_reg ^ w7_reg ^ w13_rot15;

  // P1(X) = X ^ (X<<<15) ^ (X<<<23)
  wire [31 : 0] p1_out;
  assign p1_out = p1_in ^ {p1_in[16:0], p1_in[31:17]}
                        ^ {p1_in[8:0],  p1_in[31:9]};

  // New word: P1(...) ^ (W_{j-13}<<<7) ^ W_{j-6}
  wire [31 : 0] w_new;
  assign w_new = p1_out ^ w3_rot7 ^ w10_reg;


  //----------------------------------------------------------------
  // Concurrent connectivity for ports.
  //----------------------------------------------------------------
  assign w   = w0_reg;
  assign w_p = w0_reg ^ w4_reg;


  //----------------------------------------------------------------
  // reg_update
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin : reg_update
      if (!reset_n)
        begin
          w0_reg  <= 32'h0;  w1_reg  <= 32'h0;
          w2_reg  <= 32'h0;  w3_reg  <= 32'h0;
          w4_reg  <= 32'h0;  w5_reg  <= 32'h0;
          w6_reg  <= 32'h0;  w7_reg  <= 32'h0;
          w8_reg  <= 32'h0;  w9_reg  <= 32'h0;
          w10_reg <= 32'h0;  w11_reg <= 32'h0;
          w12_reg <= 32'h0;  w13_reg <= 32'h0;
          w14_reg <= 32'h0;  w15_reg <= 32'h0;
        end
      else if (init)
        begin
          w0_reg  <= block[511 : 480];
          w1_reg  <= block[479 : 448];
          w2_reg  <= block[447 : 416];
          w3_reg  <= block[415 : 384];
          w4_reg  <= block[383 : 352];
          w5_reg  <= block[351 : 320];
          w6_reg  <= block[319 : 288];
          w7_reg  <= block[287 : 256];
          w8_reg  <= block[255 : 224];
          w9_reg  <= block[223 : 192];
          w10_reg <= block[191 : 160];
          w11_reg <= block[159 : 128];
          w12_reg <= block[127 :  96];
          w13_reg <= block[95  :  64];
          w14_reg <= block[63  :  32];
          w15_reg <= block[31  :   0];
        end
      else if (next)
        begin
          w0_reg  <= w1_reg;   w1_reg  <= w2_reg;
          w2_reg  <= w3_reg;   w3_reg  <= w4_reg;
          w4_reg  <= w5_reg;   w5_reg  <= w6_reg;
          w6_reg  <= w7_reg;   w7_reg  <= w8_reg;
          w8_reg  <= w9_reg;   w9_reg  <= w10_reg;
          w10_reg <= w11_reg;  w11_reg <= w12_reg;
          w12_reg <= w13_reg;  w13_reg <= w14_reg;
          w14_reg <= w15_reg;  w15_reg <= w_new;
        end
    end // reg_update

endmodule // sm3_w_mem

`default_nettype wire

//======================================================================
// EOF sm3_w_mem.v
//======================================================================
