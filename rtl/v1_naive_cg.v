// ============================================================================
// LAB8_DESIGN - Coupling Network      (version 1 : straightforward baseline)
//   store all six matrices, then compute one element per cycle with plain
//   operators (two 16-cycle passes), then output.  latency = 33 cycles.
//   clock gating: one gate per stored matrix / result matrix.
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
reg         run, bwd;
reg  [7:0]  t;                         // 0..95 input, 96..111 pass 1, 112..127 pass 2, 128..159 output
wire [3:0]  e   = t[3:0];
wire [3:0]  ph  = t[7:4];
wire        fwd = ~bwd;
reg  [7:0]  A [0:15], B [0:15];
reg  [3:0]  F1[0:15], H1[0:15], F2[0:15], H2[0:15];
reg  [11:0] R1[0:15], R2[0:15];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin run <= 1'b0; t <= 8'd0; end
    else if (run) begin
        if (t == 8'd159) begin run <= 1'b0; t <= 8'd0; end
        else t <= t + 8'd1;
    end
    else if (in_valid) run <= 1'b1;
end

wire en_task = ~run;
wire en_a  = run & (ph == 4'd0), en_b  = run & (ph == 4'd1);
wire en_f1 = run & (ph == 4'd2), en_h1 = run & (ph == 4'd3);
wire en_f2 = run & (ph == 4'd4), en_h2 = run & (ph == 4'd5);
wire en_r1 = run & (ph == 4'd6), en_r2 = run & (ph == 4'd7);
wire outph = run & (ph >= 4'd8);
wire en_o  = outph | out_valid;
wire g_task, g_a, g_b, g_f1, g_h1, g_f2, g_h2, g_r1, g_r2, g_o;
GATED_OR GATED_task (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_task), .RST_N(rst_n), .CLOCK_GATED(g_task));
GATED_OR GATED_a  (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_a ), .RST_N(rst_n), .CLOCK_GATED(g_a));
GATED_OR GATED_b  (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_b ), .RST_N(rst_n), .CLOCK_GATED(g_b));
GATED_OR GATED_f1 (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_f1), .RST_N(rst_n), .CLOCK_GATED(g_f1));
GATED_OR GATED_h1 (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_h1), .RST_N(rst_n), .CLOCK_GATED(g_h1));
GATED_OR GATED_f2 (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_f2), .RST_N(rst_n), .CLOCK_GATED(g_f2));
GATED_OR GATED_h2 (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_h2), .RST_N(rst_n), .CLOCK_GATED(g_h2));
GATED_OR GATED_r1 (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_r1), .RST_N(rst_n), .CLOCK_GATED(g_r1));
GATED_OR GATED_r2 (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_r2), .RST_N(rst_n), .CLOCK_GATED(g_r2));
GATED_OR GATED_o  (.CLOCK(clk), .SLEEP_CTRL(cg_en & ~en_o ), .RST_N(rst_n), .CLOCK_GATED(g_o));

always @(posedge g_task or negedge rst_n) begin
    if (!rst_n) bwd <= 1'b0;
    else if (en_task & in_valid) bwd <= in_data[0];
end
always @(posedge g_a)  if (en_a)  A [e] <= in_data;
always @(posedge g_b)  if (en_b)  B [e] <= in_data;
always @(posedge g_f1) if (en_f1) F1[e] <= in_data[3:0];
always @(posedge g_h1) if (en_h1) H1[e] <= in_data[3:0];
always @(posedge g_f2) if (en_f2) F2[e] <= in_data[3:0];
always @(posedge g_h2) if (en_h2) H2[e] <= in_data[3:0];

// ---- one element (i, j) per cycle ----
wire [1:0]  i = e[3:2], j = e[1:0];
wire        p2    = ph[0];                              // 0: pass 1, 1: pass 2
wire        use2  = fwd ? p2 : ~p2;                     // coefficient set F2/H2
wire [11:0] m0 = p2 ? R1[{2'd0, j}] : (fwd ? {4'd0, A[{2'd0, j}]} : {4'd0, B[{2'd0, j}]});
wire [11:0] m1 = p2 ? R1[{2'd1, j}] : (fwd ? {4'd0, A[{2'd1, j}]} : {4'd0, B[{2'd1, j}]});
wire [11:0] m2 = p2 ? R1[{2'd2, j}] : (fwd ? {4'd0, A[{2'd2, j}]} : {4'd0, B[{2'd2, j}]});
wire [11:0] m3 = p2 ? R1[{2'd3, j}] : (fwd ? {4'd0, A[{2'd3, j}]} : {4'd0, B[{2'd3, j}]});
wire [3:0]  f0 = use2 ? F2[{i, 2'd0}] : F1[{i, 2'd0}],  h0 = use2 ? H2[{i, 2'd0}] : H1[{i, 2'd0}];
wire [3:0]  f1 = use2 ? F2[{i, 2'd1}] : F1[{i, 2'd1}],  h1 = use2 ? H2[{i, 2'd1}] : H1[{i, 2'd1}];
wire [3:0]  f2 = use2 ? F2[{i, 2'd2}] : F1[{i, 2'd2}],  h2 = use2 ? H2[{i, 2'd2}] : H1[{i, 2'd2}];
wire [3:0]  f3 = use2 ? F2[{i, 2'd3}] : F1[{i, 2'd3}],  h3 = use2 ? H2[{i, 2'd3}] : H1[{i, 2'd3}];
wire [17:0] sx = f0 * m0 + f1 * m1 + f2 * m2 + f3 * m3;
wire [3:0]  X  = sx % 4'd15 + 4'd1;
wire [7:0]  Y  = h0 * m0[7:0] + h1 * m1[7:0] + h2 * m2[7:0] + h3 * m3[7:0];
wire [7:0]  ea = A[e], eb = B[e];
wire [7:0]  el = (fwd ^ p2) ? eb : ea;                 // fwd: B then A ; bwd: A then B
wire [11:0] res = fwd ? (X * el) ^ {4'd0, Y} : {4'd0, (el ^ Y) / X};
always @(posedge g_r1) if (en_r1) R1[e] <= res;
always @(posedge g_r2) if (en_r2) R2[e] <= res;

wire [11:0] o1 = R1[e], o2 = R2[e];
always @(posedge g_o or negedge rst_n) begin
    if (!rst_n) begin out_valid <= 1'b0; out_data <= 12'd0; end
    else if (en_o) begin
        out_valid <= outph;
        if (!outph) out_data <= 12'd0;
        else        out_data <= (ph[0] ^ fwd) ? o2 : o1;   // fwd: R2 (OUT_A) then R1 ; bwd: R1 then R2
    end
end
endmodule
