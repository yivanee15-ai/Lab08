// ============================================================================
// LAB8_DESIGN  -  Coupling Network                                 (version 8)
//
//   run/k   : k = 0..127 is the cycle index after the task cycle
//             k[6:4] = phase : 0 A, 1 B, 2 F1, 3 H1, 4 F2, 5 H2, 6 OUT_A, 7 OUT_B
//   WA/WB   : 16 x 12-bit words {hi[3:0], lo[7:0]}
//             forward : WA = A -> OUT_A                 WB = B -> Mid_B
//             backward: WA = {F2, A -> Mid_A}           WB = {F1, B}
//   HS      : four 16-bit coefficient rows : forward F1 / F2 rows, backward H1
//   s / h   : buffer of the H row that is being received (3-nibble shift + 4-nibble hold)
//   P       : pipeline register {X, Y, element} between the two stages
//
//   One element per cycle, two stages:
//     stage 1 : read one column of the operand matrix (4 words) and the element to update,
//               P <- { X = 1 + (F row . column) mod 15 ,  Y = (H row . column) mod 256 ,  element }
//     stage 2 : forward  : word <- (P.X * P.el) ^ P.Y              (Mid_B, then OUT_A)
//               backward : word <- (P.el ^ P.Y) / P.X              (Mid_A), or straight to out_data (OUT_B)
//   stage 1 of row i runs in the 4 cycles after its H row has arrived; backward OUT_B is
//   computed just in time for the output (k = 108, 112..126).
//   Mod 15 uses end-around-carry arithmetic (2^4 = 1 mod 15).
//   Sleep controls only depend on registers (run, k, task), never on inputs.
// ============================================================================
module LAB8_DESIGN(
    input             clk,
    input             rst_n,
    input             in_valid,
    input      [7:0]  in_data,
    output reg        out_valid,
    output reg [11:0] out_data
);

// ------------------------------------------------------------------ functions
function [3:0] eac;                 // end-around-carry add : (a + b) mod 15, 15 is an alias of 0
    input [3:0] a, b;
    reg   [4:0] t;
    begin t = a + b; eac = t[3:0] + t[4]; end
endfunction

function [11:0] mux4w;             // 4:1 mux of 12-bit words, v = {w3,w2,w1,w0}
    input [47:0] v;
    input [1:0]  sel;
    begin
        case (sel)
            2'd0: mux4w = v[11: 0];
            2'd1: mux4w = v[23:12];
            2'd2: mux4w = v[35:24];
            default: mux4w = v[47:36];
        endcase
    end
endfunction

function [15:0] mux4r;             // 4:1 mux of 16-bit rows
    input [63:0] v;
    input [1:0]  sel;
    begin
        case (sel)
            2'd0: mux4r = v[15: 0];
            2'd1: mux4r = v[31:16];
            2'd2: mux4r = v[47:32];
            default: mux4r = v[63:48];
        endcase
    end
endfunction

function [7:0] div8;                // unsigned 8-bit / 4-bit restoring divider (divisor is never 0)
    input [7:0] n;
    input [3:0] d;
    reg   [4:0] r, df;
    integer     b;
    begin
        r = 5'd0;
        for (b = 7; b >= 0; b = b - 1) begin
            r  = {r[3:0], n[b]};
            df = r - {1'b0, d};
            div8[b] = ~df[4];
            if (~df[4]) r = df;
        end
    end
endfunction

// ------------------------------------------------------------------ control
reg         run;
reg  [6:0]  k;
reg         bwd;                                   // task_num
wire        fwd  = ~bwd;
wire [2:0]  ph   = k[6:4];
wire [1:0]  ro   = k[3:2];                         // row of input / output element
wire [1:0]  kc   = k[1:0];
wire [4:0]  cq   = k[6:2] - 5'd1;                  // stage 1 runs 4 cycles behind the input
wire [2:0]  cph  = cq[4:2];
wire [1:0]  ri   = cq[1:0];
wire [6:0]  k2   = k - 7'd5;                       // stage 2 runs 5 cycles behind the input
wire [2:0]  cph2 = k2[6:4];

wire outph  = run & ph[2] & ph[1];
wire s1h1   = run & fwd & (cph == 3'd3);           // stage 1, H1 rows (forward)   k = 52..67
wire s1h2   = run &       (cph == 3'd5);           // stage 1, H2 rows             k = 84..99
wire late   = run & bwd & (ph == 3'd7);            // backward OUT_B window        k = 112..127
wire s1ob   = run & bwd & ((k[6:2] == 5'd27 & kc == 2'd0) | (late & ~&k[3:0]));   // k = 108, 112..126
wire s1     = s1h1 | s1h2 | s1ob;
wire w2b    = run & fwd & (cph2 == 3'd3);          // stage 2 write to WB          k = 53..68
wire w2a    = run &       (cph2 == 3'd5);          // stage 2 write to WA          k = 85..100
wire selb   = s1h2;                                // operand column from WB, element from WA
wire [3:0]  nxt  = k[3:0] + 4'd1;
wire [1:0]  nrow = late ? nxt[3:2] : 2'd0;         // row of the OUT_B element in stage 1
wire [1:0]  trow = s1ob ? nrow : ri;
wire [1:0]  col  = late ? nxt[1:0] : kc;                          // column that is read
wire strm   = run & ((ph == 3'd5) | (fwd & (ph == 3'd3)));         // H rows used on the fly
wire in_a   = run & (ph == 3'd0);
wire in_b   = run & (ph == 3'd1);
wire in_f1  = run & bwd & (ph == 3'd2);            // backward: F1 -> WB.hi, F2 -> WA.hi
wire in_f2  = run & bwd & (ph == 3'd4);
wire in_hs  = run & (bwd ? (ph == 3'd3) : (ph == 3'd2) | (ph == 3'd4));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin run <= 1'b0; k <= 7'd0; end
    else if (run) begin
        k <= k + 7'd1;                             // 127 -> 0
        if (&k) run <= 1'b0;
    end
    else if (in_valid) run <= 1'b1;
end

wire gclk_task;
assign gclk_task = clk;
always @(posedge gclk_task or negedge rst_n) begin
    if (!rst_n) bwd <= 1'b0;
    else if (!run & in_valid) bwd <= in_data[0];
end

// ------------------------------------------------------------------ storage
reg  [191:0] WA, WB;                               // word n = [12n +: 12]
reg  [63:0]  HS;                                   // row  r = [16r +: 16] = {c0,c1,c2,c3}
reg  [11:0]  s;
reg  [15:0]  h;
reg  [3:0]   PX;
reg  [7:0]   PY, PT;
wire [7:0]   wd_lo;
wire [3:0]   wd_hi;

wire        in_w   = in_a | in_b | in_f1 | in_f2;
wire [3:0]  waddr  = in_w ? k[3:0] : k2[3:0];
wire        wa_lo  = in_a  | w2a;
wire        wa_hi  = in_f2 | (w2a & fwd);
wire        wb_lo  = in_b  | w2b;
wire        wb_hi  = in_f1 | w2b;

wire [7:0]  gclk_a, gclk_b;
wire [47:0] busA, busB;                            // write data, only driven towards the addressed row
genvar g;
generate
for (g = 0; g < 4; g = g + 1) begin : B
    wire rhit = (waddr[3:2] == g);
    assign busA[12*g +: 12] = {wd_hi & {4{rhit & wa_hi}}, wd_lo & {8{rhit & wa_lo}}};
    assign busB[12*g +: 12] = {wd_hi & {4{rhit & wb_hi}}, wd_lo & {8{rhit & wb_lo}}};
end
for (g = 0; g < 8; g = g + 1) begin : G         // one clock gate per pair of words (2 x 12 flops)
    wire phit = (waddr[3:1] == g);
    wire a_en = phit & (wa_lo | wa_hi);
    wire b_en = phit & (wb_lo | wb_hi);
    assign gclk_a[g] = clk;
    assign gclk_b[g] = clk;
end
for (g = 0; g < 16; g = g + 1) begin : W
    wire hit  = (waddr == g);
    wire a_lo = hit & wa_lo, a_hi = hit & wa_hi;
    wire b_lo = hit & wb_lo, b_hi = hit & wb_hi;
    wire [11:0] da = busA[12*(g/4) +: 12];
    wire [11:0] db = busB[12*(g/4) +: 12];
    always @(posedge gclk_a[g/2]) begin
        if (a_lo) WA[12*g   +: 8] <= da[7:0];
        if (a_hi) WA[12*g+8 +: 4] <= da[11:8];
    end
    always @(posedge gclk_b[g/2]) begin
        if (b_lo) WB[12*g   +: 8] <= db[7:0];
        if (b_hi) WB[12*g+8 +: 4] <= db[11:8];
    end
end
for (g = 0; g < 4; g = g + 1) begin : R
    wire hs_en = in_hs & (ro == g);
    wire gclk_hs;
    assign gclk_hs = clk;
    always @(posedge gclk_hs) begin
        if (hs_en) HS[16*g +: 16] <= {HS[16*g +: 12], in_data[3:0]};
    end
end
endgenerate

wire s_en = strm;
wire h_en = strm & (kc == 2'd3);
wire gclk_s, gclk_h, gclk_p;
assign gclk_s = clk;
assign gclk_h = clk;
assign gclk_p = clk;
always @(posedge gclk_s) begin
    if (s_en) s <= {s[7:0], in_data[3:0]};
end
always @(posedge gclk_h) begin
    if (h_en) h <= {s, in_data[3:0]};
end

// ------------------------------------------------------------------ stage 1 : read
wire [47:0] colA, colB;                            // one column of each matrix, row r = [12r +: 12]
wire [63:0] f1all, f2all;                          // F nibbles kept in the hi fields (backward)
generate
for (g = 0; g < 4; g = g + 1) begin : C
    // a row only follows the column select when one of its words is really needed (quiet muxes otherwise)
    wire rd_a = (s1 & (~selb | (trow == g))) | (outph & ~ph[0] & (ro == g));
    wire rd_b = (s1 & ( selb | (trow == g))) | (outph &  ph[0] & fwd & (ro == g));
    assign colA[12*g +: 12] = mux4w(WA[48*g +: 48], col & {2{rd_a}});
    assign colB[12*g +: 12] = mux4w(WB[48*g +: 48], col & {2{rd_b}});
    assign f1all[16*g +: 16] = {WB[48*g+8 +: 4], WB[48*g+20 +: 4], WB[48*g+32 +: 4], WB[48*g+44 +: 4]};
    assign f2all[16*g +: 16] = {WA[48*g+8 +: 4], WA[48*g+20 +: 4], WA[48*g+32 +: 4], WA[48*g+44 +: 4]};
end
endgenerate
wire [47:0] S   = selb ? colB : colA;              // operand column
wire [11:0] T   = mux4w(selb ? colA : colB, trow); // element that is updated
wire [11:0] O   = mux4w(ph[0] ? colB : colA, ro);  // element that is output (forward, backward OUT_A)

// ------------------------------------------------------------------ stage 1 : X = 1 + (sum c*m) mod 15
wire        keep_hi = fwd & s1h2;                  // only Mid_B is a 12-bit operand
wire [15:0] xrow    = fwd ? mux4r(HS, ri) : mux4r(s1ob ? f1all : f2all, trow);
wire [15:0] xc      = s1 ? xrow : 16'd0;
wire [47:0] SX      = S & {4{{4{keep_hi}}, {8{s1}}}};
// each operand column word is first folded to 4 bits (mod 15), then the 16 partial products
// c[b] ? rotl(m, b) : 0  (x2 mod 15 is a 1-bit rotate) and the constant 1 are summed by a
// balanced carry-save tree whose carries wrap around; one end-around-carry adder finishes the job.
wire [15:0] xm;
generate
for (g = 0; g < 4; g = g + 1) begin : XM
    assign xm[4*g +: 4] = eac(eac(SX[12*g+8 +: 4], SX[12*g+4 +: 4]), SX[12*g +: 4]);
end
endgenerate
wire [67:0] xop;                                   // 17 operands of 4 bits
generate
for (g = 0; g < 4; g = g + 1) begin : XP4          // row g uses coefficient nibble xc[15-4g -: 4] (c0 first)
    wire [3:0] m = xm[4*g +: 4];
    wire [3:0] c = xc[15-4*g -: 4];
    assign xop[16*g    +: 4] = m                & {4{c[0]}};
    assign xop[16*g+4  +: 4] = {m[2:0], m[3]}   & {4{c[1]}};
    assign xop[16*g+8  +: 4] = {m[1:0], m[3:2]} & {4{c[2]}};
    assign xop[16*g+12 +: 4] = {m[0],   m[3:1]} & {4{c[3]}};
end
endgenerate
assign xop[67:64] = 4'd1;
// balanced carry-save (3:2) tree, the carry vector is rotated by one bit (x2 mod 15)
wire [3:0] xs0 = xop[3:0] ^ xop[7:4] ^ xop[11:8];
wire [3:0] xk0 = (xop[3:0] & xop[7:4]) | (xop[3:0] & xop[11:8]) | (xop[7:4] & xop[11:8]);
wire [3:0] xs1 = xop[15:12] ^ xop[19:16] ^ xop[23:20];
wire [3:0] xk1 = (xop[15:12] & xop[19:16]) | (xop[15:12] & xop[23:20]) | (xop[19:16] & xop[23:20]);
wire [3:0] xs2 = xop[27:24] ^ xop[31:28] ^ xop[35:32];
wire [3:0] xk2 = (xop[27:24] & xop[31:28]) | (xop[27:24] & xop[35:32]) | (xop[31:28] & xop[35:32]);
wire [3:0] xs3 = xop[39:36] ^ xop[43:40] ^ xop[47:44];
wire [3:0] xk3 = (xop[39:36] & xop[43:40]) | (xop[39:36] & xop[47:44]) | (xop[43:40] & xop[47:44]);
wire [3:0] xs4 = xop[51:48] ^ xop[55:52] ^ xop[59:56];
wire [3:0] xk4 = (xop[51:48] & xop[55:52]) | (xop[51:48] & xop[59:56]) | (xop[55:52] & xop[59:56]);
wire [3:0] xs5 = xs0 ^ {xk0[2:0], xk0[3]} ^ xs1;
wire [3:0] xk5 = (xs0 & {xk0[2:0], xk0[3]}) | (xs0 & xs1) | ({xk0[2:0], xk0[3]} & xs1);
wire [3:0] xs6 = {xk1[2:0], xk1[3]} ^ xs2 ^ {xk2[2:0], xk2[3]};
wire [3:0] xk6 = ({xk1[2:0], xk1[3]} & xs2) | ({xk1[2:0], xk1[3]} & {xk2[2:0], xk2[3]}) | (xs2 & {xk2[2:0], xk2[3]});
wire [3:0] xs7 = xs3 ^ {xk3[2:0], xk3[3]} ^ xs4;
wire [3:0] xk7 = (xs3 & {xk3[2:0], xk3[3]}) | (xs3 & xs4) | ({xk3[2:0], xk3[3]} & xs4);
wire [3:0] xs8 = {xk4[2:0], xk4[3]} ^ xop[63:60] ^ xop[67:64];
wire [3:0] xk8 = ({xk4[2:0], xk4[3]} & xop[63:60]) | ({xk4[2:0], xk4[3]} & xop[67:64]) | (xop[63:60] & xop[67:64]);
wire [3:0] xs9 = xs5 ^ {xk5[2:0], xk5[3]} ^ xs6;
wire [3:0] xk9 = (xs5 & {xk5[2:0], xk5[3]}) | (xs5 & xs6) | ({xk5[2:0], xk5[3]} & xs6);
wire [3:0] xs10 = {xk6[2:0], xk6[3]} ^ xs7 ^ {xk7[2:0], xk7[3]};
wire [3:0] xk10 = ({xk6[2:0], xk6[3]} & xs7) | ({xk6[2:0], xk6[3]} & {xk7[2:0], xk7[3]}) | (xs7 & {xk7[2:0], xk7[3]});
wire [3:0] xs11 = xs9 ^ {xk9[2:0], xk9[3]} ^ xs10;
wire [3:0] xk11 = (xs9 & {xk9[2:0], xk9[3]}) | (xs9 & xs10) | ({xk9[2:0], xk9[3]} & xs10);
wire [3:0] xs12 = {xk10[2:0], xk10[3]} ^ xs8 ^ {xk8[2:0], xk8[3]};
wire [3:0] xk12 = ({xk10[2:0], xk10[3]} & xs8) | ({xk10[2:0], xk10[3]} & {xk8[2:0], xk8[3]}) | (xs8 & {xk8[2:0], xk8[3]});
wire [3:0] xs13 = xs11 ^ {xk11[2:0], xk11[3]} ^ xs12;
wire [3:0] xk13 = (xs11 & {xk11[2:0], xk11[3]}) | (xs11 & xs12) | ({xk11[2:0], xk11[3]} & xs12);
wire [3:0] xs14 = xs13 ^ {xk13[2:0], xk13[3]} ^ {xk12[2:0], xk12[3]};
wire [3:0] xk14 = (xs13 & {xk13[2:0], xk13[3]}) | (xs13 & {xk12[2:0], xk12[3]}) | ({xk13[2:0], xk13[3]} & {xk12[2:0], xk12[3]});
wire [3:0]  X = eac(xs14, {xk14[2:0], xk14[3]});         // always 1..15 (the constant operand keeps it non-zero)

// ------------------------------------------------------------------ stage 1 : Y = (sum c*m) mod 256
wire [15:0] yc = s1 ? (s1ob ? mux4r(HS, nrow) : h) : 16'd0;
wire [7:0]  Y  = yc[15:12] * S[ 7: 0] + yc[11: 8] * S[19:12]
               + yc[ 7: 4] * S[31:24] + yc[ 3: 0] * S[43:36];

always @(posedge gclk_p) begin
    if (s1) begin PX <= X; PY <= Y; PT <= T[7:0]; end
end

// ------------------------------------------------------------------ stage 2 : update
wire [11:0] prod = (PX & {4{fwd}}) * PT;
wire [7:0]  quot = div8((PT ^ PY) & {8{bwd}}, PX & {4{bwd}});
assign wd_lo = (in_a | in_b) ? in_data : (fwd ? prod[7:0] ^ PY : quot);
assign wd_hi = (in_f1 | in_f2) ? in_data[3:0] : prod[11:8];

// ------------------------------------------------------------------ output
wire o_en = outph | out_valid;
wire gclk_o;
assign gclk_o = clk;
always @(posedge gclk_o or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; out_data <= 12'd0; end
    else if (o_en) begin
        out_valid <= outph;
        if (!outph)      out_data <= 12'd0;
        else if (fwd)    out_data <= O;
        else             out_data <= ph[0] ? {4'd0, quot} : {4'd0, O[7:0]};
    end
end

endmodule
