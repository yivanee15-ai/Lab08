(* techmap_celltype = "$_NOT_" *)
module _tm_G_NOT(input A, output Y); G_NOT _TECHMAP_REPLACE_ (.A(A), .Y(Y)); endmodule
(* techmap_celltype = "$_AND_" *)
module _tm_G_AND(input A,B, output Y); G_AND _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_NAND_" *)
module _tm_G_NAND(input A,B, output Y); G_NAND _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_OR_" *)
module _tm_G_OR(input A,B, output Y); G_OR _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_NOR_" *)
module _tm_G_NOR(input A,B, output Y); G_NOR _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_ANDNOT_" *)
module _tm_G_ANDN(input A,B, output Y); G_ANDN _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_ORNOT_" *)
module _tm_G_ORN(input A,B, output Y); G_ORN _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_XOR_" *)
module _tm_G_XOR(input A,B, output Y); G_XOR _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_XNOR_" *)
module _tm_G_XNOR(input A,B, output Y); G_XNOR _TECHMAP_REPLACE_ (.A(A), .B(B), .Y(Y)); endmodule
(* techmap_celltype = "$_MUX_" *)
module _tm_G_MUX(input A,B,S, output Y); G_MUX _TECHMAP_REPLACE_ (.A(A), .B(B), .S(S), .Y(Y)); endmodule
(* techmap_celltype = "$_DFF_P_" *)
module _tm_G_DFF(input C,D, output Q); G_DFF _TECHMAP_REPLACE_ (.C(C), .D(D), .Q(Q)); endmodule
(* techmap_celltype = "$_DFF_PN0_" *)
module _tm_G_DFFR(input C,D,R, output Q); G_DFFR _TECHMAP_REPLACE_ (.C(C), .D(D), .R(R), .Q(Q)); endmodule
(* techmap_celltype = "$_DFFE_PP_" *)
module _tm_G_DFFE(input C,D,E, output Q); G_DFFE _TECHMAP_REPLACE_ (.C(C), .D(D), .E(E), .Q(Q)); endmodule
(* techmap_celltype = "$_DFFE_PN0P_" *)
module _tm_G_DFFER(input C,D,E,R, output Q); G_DFFER _TECHMAP_REPLACE_ (.C(C), .D(D), .E(E), .R(R), .Q(Q)); endmodule
