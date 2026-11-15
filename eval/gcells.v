`timescale 1ns/10ps
module G_NOT(input A, output Y); assign #0.06 Y = ~A; endmodule
module G_AND(input A,B, output Y); assign #0.14 Y = A&B; endmodule
module G_NAND(input A,B, output Y); assign #0.08 Y = ~(A&B); endmodule
module G_OR(input A,B, output Y); assign #0.14 Y = A|B; endmodule
module G_NOR(input A,B, output Y); assign #0.08 Y = ~(A|B); endmodule
module G_ANDN(input A,B, output Y); assign #0.14 Y = A&~B; endmodule
module G_ORN(input A,B, output Y); assign #0.14 Y = A|~B; endmodule
module G_XOR(input A,B, output Y); assign #0.18 Y = A^B; endmodule
module G_XNOR(input A,B, output Y); assign #0.18 Y = ~(A^B); endmodule
module G_MUX(input A,B,S, output Y); assign #0.18 Y = S?B:A; endmodule
module G_DFF(input C,D, output reg Q); always @(posedge C) Q <= #0.25 D; endmodule
module G_DFFR(input C,D,R, output reg Q); always @(posedge C or negedge R) if (!R) Q <= #0.25 1'b0; else Q <= #0.25 D; endmodule
module G_DFFE(input C,D,E, output reg Q); always @(posedge C) if (E) Q <= #0.25 D; endmodule
module G_DFFER(input C,D,E,R, output reg Q); always @(posedge C or negedge R) if (!R) Q <= #0.25 1'b0; else if (E) Q <= #0.25 D; endmodule
