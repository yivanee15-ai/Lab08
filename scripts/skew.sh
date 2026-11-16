#!/bin/bash
# Gate-level robustness against gated-clock delay: every GATED_OR instance gets its own random
# latch / OR delay (OR delay in [base, 2*base]); the mapped netlist is run with the real PATTERN.
# usage: scripts/skew.sh <design without the GATED_OR include> [npat]
cd "$(dirname "$0")/.."
SRC=$1; NP=${2:-60}; N=$(basename $SRC .v); W=build/$N
scripts/eval.sh $SRC $NP >/dev/null 2>&1
for base in 0.0 0.2 0.4 0.6 0.8 1.0 1.5; do for sd in 1 2; do
cat > build/gor.v <<GOR
\`timescale 1ns/10ps
module GATED_OR(input CLOCK, SLEEP_CTRL, RST_N, output CLOCK_GATED);
reg l; real dl, dq; integer sd, i; reg [8*200:1] nm;
initial begin \$sformat(nm, "%m"); sd = $sd; for (i = 1; i <= 200; i = i + 1) sd = sd * 31 + nm[8*i -: 8];
  dq = 0.3 * $base * (1.0 + (\$unsigned(\$random(sd)) % 100) / 100.0); dl = $base * (1.0 + (\$unsigned(\$random(sd)) % 100) / 100.0); end
wire lq; assign #(dq) lq = l;
always @(*) if (!RST_N) l = 0; else if (CLOCK) l = SLEEP_CTRL;
wire g = CLOCK | lq; reg gd; always @(g) gd <= #(dl) g;
assign CLOCK_GATED = gd;
endmodule
GOR
for m in "-DCG" "-DCG -DCG_EN=1'b0"; do iverilog -g2005 -o build/sk.vvp $m $W/net_cg.v eval/gcells.v build/gor.v 00_TESTBED/TESTBED.v 00_TESTBED/PATTERN.v 2>/dev/null; (cd $W && printf "base %s seed %s %-20s " $base $sd "$m" && vvp -n ../sk.vvp | grep -E "OK|VIOL|WRONG" | head -1 | cut -c1-70); done; done; done
