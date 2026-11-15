#!/bin/bash
# Area / depth / power PROXY for one design version (open-source flow, NOT the course tools):
#   yosys generic gate netlist (AND/OR/XOR/MUX/DFF..., 1:1 area table of an open 0.18um library)
#   delay-annotated gate-level simulation with the real PATTERN -> toggle (incl. glitch) based energy
# Good for RELATIVE comparison between versions only.
# usage: scripts/eval.sh rtl/<version>.v [npat]      (PWOPT=-v for a profile)
set -e
cd "$(dirname "$0")/.."
SRC=$1; NP=${2:-60}
N=$(basename $SRC .v); W=build/$N; mkdir -p $W
python3 scripts/mk_wocg.py $SRC $W/wocg.v >/dev/null
( cd $W && python3 ../../golden/golden.py $NP 7 . >/dev/null )
for M in cg wocg; do
  if [ $M = cg ]; then RD="read_verilog eval/gbb.v; read_verilog $SRC"; else RD="read_verilog eval/gbb.v; read_verilog $W/wocg.v"; fi
  yosys -q -l $W/syn_$M.log -p "$RD; synth -top LAB8_DESIGN -flatten; opt -full; ltp -noff; techmap -map eval/gmap.v; opt_clean -purge; setundef -zero; rename -enumerate -pattern zn%; stat; write_verilog -noattr $W/net_$M.v; write_json $W/net_$M.json" >/dev/null
done
sim() { # name netlist defines
  iverilog -g2005 -o $W/g_$1.vvp -DVCD=\"g_$1.vcd\" $3 $2 eval/gcells.v 00_TESTBED/GATED_OR.v 00_TESTBED/TESTBED.v 00_TESTBED/PATTERN.v 2>&1 | grep -v "timescale" || true
  ( cd $W && vvp -n g_$1.vvp | grep -E "OK|VIOLATION|WRONG|MISMATCH" | sed "s/^/  gate-sim $1: /" )
}
sim wocg $W/net_wocg.v ""
sim cg1  $W/net_cg.v "-DCG"
python3 scripts/power.py $N $W $PWOPT
rm -f $W/*.vcd
