`timescale 1ns / 1ps
module mul_64b_wrapper(
    input [63:0]    a,
    input [63:0]    b,

    output [127:0]  p
);

assign p = a * b;

endmodule