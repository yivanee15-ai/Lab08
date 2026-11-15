#!/bin/bash
# "SEC-lite": drive the clock-gated design (cg_en = 1 or random) and the wocg design with the SAME
# completely random stimulus (in_valid is NOT protocol compliant) and compare the outputs every cycle.
# usage: scripts/lockstep.sh rtl/<version>.v [cycles]
set -e
cd "$(dirname "$0")/.."
SRC=$1; NC=${2:-400000}
W=build/$(basename $SRC .v); mkdir -p $W
python3 scripts/mk_wocg.py $SRC $W/wocg.v >/dev/null
sed 's/module LAB8_DESIGN(/module LAB8_DESIGN_W(/' $W/wocg.v > $W/wocg_w.v
cat > $W/lock_tb.v <<TB
\`timescale 1ns/10ps
module lock_tb;
reg clk = 0, rst_n = 1, in_valid = 0, cg_en = 1; reg [7:0] in_data = 0;
wire ov1, ov2; wire [11:0] od1, od2;
LAB8_DESIGN   u_cg (.clk(clk), .rst_n(rst_n), .cg_en(cg_en), .in_valid(in_valid), .in_data(in_data), .out_valid(ov1), .out_data(od1));
LAB8_DESIGN_W u_wo (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_data(in_data), .out_valid(ov2), .out_data(od2));
always #7.5 clk = ~clk;
integer i, seed = 1, mode, nv = 0;
initial begin
    #3 rst_n = 0; #20 rst_n = 1;
    for (i = 0; i < $NC; i = i + 1) begin
        @(negedge clk);
        if (ov1 !== ov2 || od1 !== od2) begin \$display("LOCKSTEP MISMATCH at cycle %0d: %b %h vs %b %h", i, ov1, od1, ov2, od2); \$finish; end
        if (ov1 === 1'b1) nv = nv + 1;
        if (i % 5000 == 0) mode = {\$random(seed)} % 3;          // 0: sparse valid, 1: dense valid, 2: bursts
        in_valid = (mode == 0) ? ({\$random(seed)} % 50 == 0) : (mode == 1) ? ({\$random(seed)} % 4 != 0) : (({\$random(seed)} % 300) < 120);
        in_data  = \$random(seed);
        if (i % 977 == 0) cg_en = \$random(seed);                // cg_en itself also changes now and then
    end
    \$display("LOCKSTEP OK: %0d cycles, %0d output cycles compared", $NC, nv);
    \$finish;
end
endmodule
TB
iverilog -g2005 -o $W/lock.vvp $SRC $W/wocg_w.v 00_TESTBED/GATED_OR.v $W/lock_tb.v && vvp -n $W/lock.vvp | grep LOCKSTEP
