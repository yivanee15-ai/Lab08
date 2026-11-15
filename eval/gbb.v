(* blackbox *) module GATED_OR(input CLOCK, input SLEEP_CTRL, input RST_N, output CLOCK_GATED); endmodule
(* blackbox *) module G_NOT(input A, output Y); endmodule
(* blackbox *) module G_AND(input A,B, output Y); endmodule
(* blackbox *) module G_NAND(input A,B, output Y); endmodule
(* blackbox *) module G_OR(input A,B, output Y); endmodule
(* blackbox *) module G_NOR(input A,B, output Y); endmodule
(* blackbox *) module G_ANDN(input A,B, output Y); endmodule
(* blackbox *) module G_ORN(input A,B, output Y); endmodule
(* blackbox *) module G_XOR(input A,B, output Y); endmodule
(* blackbox *) module G_XNOR(input A,B, output Y); endmodule
(* blackbox *) module G_MUX(input A,B,S, output Y); endmodule
(* blackbox *) module G_DFF(input C,D, output Q); endmodule
(* blackbox *) module G_DFFR(input C,D,R, output Q); endmodule
(* blackbox *) module G_DFFE(input C,D,E, output Q); endmodule
(* blackbox *) module G_DFFER(input C,D,E,R, output Q); endmodule
