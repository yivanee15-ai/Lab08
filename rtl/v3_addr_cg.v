// ============================================================================
// LAB8_DESIGN  -  Coupling Network            (version 3 : element-serial,
//                 addressable word storage, one write bus, word-level gating)
//
//   run/k   : k = 0..127 is the cycle index after the task cycle
//             k[6:4] = phase : 0 A, 1 B, 2 F1, 3 H1, 4 F2, 5 H2, 6 OUT_A, 7 OUT_B
//   WA/WB   : 16 x 12-bit words {hi[3:0], lo[7:0]}
//             forward : WA = A -> {X2,A} -> OUT_A        WB = B -> {X1,B} -> Mid_B
//             backward: WA = A -> {X2,A} -> Mid_A        WB = {F1,B} -> {X1,B}
//   HS      : H1 rows (backward only)
//   s / h   : coefficient row buffer (3-nibble shift + 4-nibble hold)
//   Every compute step handles ONE element (row ri, column k[1:0]) per cycle,
//   4 cycles after its coefficient row has arrived.
// ============================================================================
module LAB8_DESIGN(
    input             clk,
    input             rst_n,
    input             cg_en,
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

function [3:0] mulm15;              // (c * m) mod 15 ; multiply by 2^n is a rotate
    input [3:0] c, m;
    reg   [3:0] p0, p1, p2, p3;
    begin
        p0 = c[0] ? m                 : 4'd0;
        p1 = c[1] ? {m[2:0], m[3]}    : 4'd0;
        p2 = c[2] ? {m[1:0], m[3:2]}  : 4'd0;
        p3 = c[3] ? {m[0],   m[3:1]}  : 4'd0;
        mulm15 = eac(eac(p0, p1), eac(p2, p3));
    end
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
wire [1:0]  col  = k[1:0];
wire [4:0]  cq   = k[6:2] - 5'd1;
wire [2:0]  cph  = cq[4:2];                        // compute phase (4 cycles behind the input)
wire [1:0]  ri   = cq[1:0];                        // row of the element being computed

wire f1c = run & fwd & (cph == 3'd2);              // WB.hi <- X1
wire h1c = run & fwd & (cph == 3'd3);              // WB    <- (hi*lo) ^ Y1        = Mid_B
wire f2c = run &       (cph == 3'd4);              // WA.hi <- X2
wire h2c = run &       (cph == 3'd5);              // WA    <- (hi*lo) ^ Y2 | (lo ^ Y2) / hi
wire xp  = run & bwd & (cph == 3'd6);              // WB.hi <- X1               (backward)
wire yp  = run & bwd & (ph  == 3'd7);              // out   <- (lo ^ Y1) / hi   (backward)
wire selb   = cph[2] & ~cph[1];                    // S = WB, T = WA  (F2 / H2 steps)
wire x_act  = f1c | f2c | xp;
wire y_act  = h1c | h2c;
wire outph  = run & ph[2] & ph[1];
wire strm   = run & (ph[2] ^ ph[1]) & (fwd | ph[2]);        // coefficients needed on the fly
wire in_a   = run & (ph == 3'd0);
wire in_b   = run & (ph == 3'd1);
wire in_f1  = run & bwd & (ph == 3'd2);
wire in_h1  = run & bwd & (ph == 3'd3);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin run <= 1'b0; k <= 7'd0; end
    else if (run) begin
        k <= k + 7'd1;                             // 127 -> 0
        if (&k) run <= 1'b0;
    end
    else if (in_valid) run <= 1'b1;
end

wire gclk_task;
GATED_OR GATED_task (.CLOCK(clk), .SLEEP_CTRL(cg_en & run), .RST_N(rst_n), .CLOCK_GATED(gclk_task));
always @(posedge gclk_task or negedge rst_n) begin
    if (!rst_n) bwd <= 1'b0;
    else if (!run & in_valid) bwd <= in_data[0];
end

// ------------------------------------------------------------------ storage
reg  [191:0] WA, WB;                               // word n = [12n +: 12]
reg  [63:0]  HS;                                   // row  r = [16r +: 16] = {c0,c1,c2,c3}
reg  [11:0]  s;
reg  [15:0]  h;
wire [7:0]   wd_lo;
wire [3:0]   wd_hi;

wire [3:0] waddr  = (in_a | in_b | in_f1) ? k[3:0] : {ri, col};
wire       wa_lo  = in_a | h2c;
wire       wa_hi  = f2c | (h2c & fwd);
wire       wb_lo  = in_b | h1c;
wire       wb_hi  = in_f1 | f1c | h1c | xp;

genvar g;
generate
for (g = 0; g < 16; g = g + 1) begin : W
    wire hit  = (waddr == g);
    wire a_lo = hit & wa_lo, a_hi = hit & wa_hi;
    wire b_lo = hit & wb_lo, b_hi = hit & wb_hi;
    wire gclk_a, gclk_b;
    GATED_OR GATED_A (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~(a_lo | a_hi)), .RST_N(rst_n), .CLOCK_GATED(gclk_a));
    GATED_OR GATED_B (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~(b_lo | b_hi)), .RST_N(rst_n), .CLOCK_GATED(gclk_b));
    always @(posedge gclk_a) begin
        if (a_lo) WA[12*g   +: 8] <= wd_lo;
        if (a_hi) WA[12*g+8 +: 4] <= wd_hi;
    end
    always @(posedge gclk_b) begin
        if (b_lo) WB[12*g   +: 8] <= wd_lo;
        if (b_hi) WB[12*g+8 +: 4] <= wd_hi;
    end
end
for (g = 0; g < 4; g = g + 1) begin : R
    wire hs_en = in_h1 & (ro == g);
    wire gclk_hs;
    GATED_OR GATED_HS (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~hs_en), .RST_N(rst_n), .CLOCK_GATED(gclk_hs));
    always @(posedge gclk_hs) begin
        if (hs_en) HS[16*g +: 16] <= {HS[16*g +: 12], in_data[3:0]};
    end
end
endgenerate

wire [63:0] f1all;                                 // F1 nibbles kept in WB.hi (backward), row r = [16r +: 16]
generate
for (g = 0; g < 4; g = g + 1) begin : FR
    assign f1all[16*g +: 16] = {WB[48*g+8 +: 4], WB[48*g+20 +: 4], WB[48*g+32 +: 4], WB[48*g+44 +: 4]};
end
endgenerate
wire [15:0] f1row = mux4r(f1all, ro);
wire s_en = strm;
wire h_en = (col == 2'd3) & (strm | (run & bwd & (ph == 3'd6)));
wire gclk_s, gclk_h;
GATED_OR GATED_s (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~s_en), .RST_N(rst_n), .CLOCK_GATED(gclk_s));
GATED_OR GATED_h (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~h_en), .RST_N(rst_n), .CLOCK_GATED(gclk_h));
always @(posedge gclk_s) begin
    if (s_en) s <= {s[7:0], in_data[3:0]};
end
always @(posedge gclk_h) begin
    if (h_en) h <= ph[2] & ph[1] ? f1row : {s, in_data[3:0]};
end

// ------------------------------------------------------------------ read : one column of each matrix
wire [47:0] colA, colB;                            // row r = [12r +: 12]
generate
for (g = 0; g < 4; g = g + 1) begin : C
    assign colA[12*g +: 12] = mux4w(WA[48*g +: 48], col);
    assign colB[12*g +: 12] = mux4w(WB[48*g +: 48], col);
end
endgenerate
wire [47:0] S   = selb ? colB : colA;              // operand column
wire [11:0] T   = mux4w(selb ? colA : colB, ri);   // element being updated
wire [11:0] OA  = mux4w(colA, ro);               // elements being output
wire [11:0] OB  = mux4w(colB, ro);

// ------------------------------------------------------------------ X unit : 1 + (sum c*m) mod 15
wire        keep_hi = fwd & selb;                  // only Mid_B is a 12-bit operand
wire [15:0] xc      = x_act ? h : 16'd0;
wire [3:0]  xm0, xm1, xm2, xm3;
assign xm0 = mulm15(xc[15:12], eac(eac(S[11: 8] & {4{keep_hi}}, S[ 7: 4]), S[ 3: 0]));
assign xm1 = mulm15(xc[11: 8], eac(eac(S[23:20] & {4{keep_hi}}, S[19:16]), S[15:12]));
assign xm2 = mulm15(xc[ 7: 4], eac(eac(S[35:32] & {4{keep_hi}}, S[31:28]), S[27:24]));
assign xm3 = mulm15(xc[ 3: 0], eac(eac(S[47:44] & {4{keep_hi}}, S[43:40]), S[39:36]));
wire [3:0]  X = eac(eac(eac(xm0, xm1), eac(xm2, xm3)), 4'd1);      // always 1..15

// ------------------------------------------------------------------ Y unit : (sum c*m) mod 256
wire [15:0] yc = yp ? mux4r(HS, ro) : (y_act ? h : 16'd0);
wire [7:0]  Y  = yc[15:12] * S[ 7: 0] + yc[11: 8] * S[19:12]
               + yc[ 7: 4] * S[31:24] + yc[ 3: 0] * S[43:36];

// ------------------------------------------------------------------ element update
wire [11:0] prod   = (T[11:8] & {4{y_act & fwd}}) * T[7:0];
wire        d_act  = yp | (h2c & bwd);
wire [11:0] D      = yp ? OB : T;
wire [7:0]  quot   = div8((D[7:0] ^ Y) & {8{d_act}}, D[11:8]);
assign wd_lo = (in_a | in_b) ? in_data : (fwd ? prod[7:0] ^ Y : quot);
assign wd_hi = in_f1 ? in_data[3:0] : (x_act ? X : prod[11:8]);

// ------------------------------------------------------------------ output
wire o_en = outph | out_valid;
wire gclk_o;
GATED_OR GATED_o (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~o_en), .RST_N(rst_n), .CLOCK_GATED(gclk_o));
always @(posedge gclk_o or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; out_data <= 12'd0; end
    else if (o_en) begin
        out_valid <= outph;
        if (!outph)      out_data <= 12'd0;
        else if (fwd)    out_data <= ph[0] ? OB : OA;
        else             out_data <= ph[0] ? {4'd0, quot} : {4'd0, OA[7:0]};
    end
end

endmodule
