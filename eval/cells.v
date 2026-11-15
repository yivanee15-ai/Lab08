// simple functional models (unit delay -> glitches are visible) of the open 0.18um cells used by the area/power proxy flow
`timescale 1ns/10ps
`define D #0.1
module AND2X1(input A,B, output Y); assign `D Y = A&B; endmodule
module AND2X2(input A,B, output Y); assign `D Y = A&B; endmodule
module AOI21X1(input A,B,C, output Y); assign `D Y = ~((A&B)|C); endmodule
module AOI22X1(input A,B,C,D, output Y); assign `D Y = ~((A&B)|(C&D)); endmodule
module BUFX2(input A, output Y); assign `D Y = A; endmodule
module BUFX4(input A, output Y); assign `D Y = A; endmodule
module INVX1(input A, output Y); assign `D Y = ~A; endmodule
module INVX2(input A, output Y); assign `D Y = ~A; endmodule
module INVX4(input A, output Y); assign `D Y = ~A; endmodule
module INVX8(input A, output Y); assign `D Y = ~A; endmodule
module NAND2X1(input A,B, output Y); assign `D Y = ~(A&B); endmodule
module NAND3X1(input A,B,C, output Y); assign `D Y = ~(A&B&C); endmodule
module NOR2X1(input A,B, output Y); assign `D Y = ~(A|B); endmodule
module NOR3X1(input A,B,C, output Y); assign `D Y = ~(A|B|C); endmodule
module OAI21X1(input A,B,C, output Y); assign `D Y = ~((A|B)&C); endmodule
module OAI22X1(input A,B,C,D, output Y); assign `D Y = ~((A|B)&(C|D)); endmodule
module OR2X1(input A,B, output Y); assign `D Y = A|B; endmodule
module OR2X2(input A,B, output Y); assign `D Y = A|B; endmodule
module XOR2X1(input A,B, output Y); assign `D Y = A^B; endmodule
module XNOR2X1(input A,B, output Y); assign `D Y = ~(A^B); endmodule
module MUX2X1(input A,B,S, output Y); assign `D Y = ~(S ? A : B); endmodule
module FAX1(input A,B,C, output YC,YS); assign `D YS = A^B^C; assign `D YC = (A&B)|(A&C)|(B&C); endmodule
module HAX1(input A,B, output YC,YS); assign `D YS = A^B; assign `D YC = A&B; endmodule
module DFFPOSX1(input CLK,D, output reg Q); always @(posedge CLK) Q <= #0.2 D; endmodule
module DFFSR(input CLK,D,R,S, output reg Q);
  always @(posedge CLK or negedge R or negedge S) if (!R) Q <= #0.2 1'b0; else if (!S) Q <= #0.2 1'b1; else Q <= #0.2 D;
endmodule
