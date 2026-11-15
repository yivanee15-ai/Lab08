#!/bin/bash
# RTL simulation of one design version in the 3 modes (wocg, cg_en=0, cg_en=1)
# usage: scripts/sim.sh rtl/v3_addr_cg.v [npat]
set -e
cd "$(dirname "$0")/.."
SRC=$1; NP=${2:-1000}
W=build/$(basename $SRC .v); mkdir -p $W
python3 scripts/mk_wocg.py $SRC $W/wocg.v
( cd $W && python3 ../../golden/golden.py $NP 2026 . >/dev/null )
run() { # name, defines..., files
  local name=$1; shift
  iverilog -g2005 -o $W/$name.vvp "$@" 00_TESTBED/TESTBED.v 00_TESTBED/PATTERN.v
  ( cd $W && printf "%-8s " $name && vvp -n $name.vvp | grep -E "OK|VIOLATION|WRONG|MISMATCH" )
}
run wocg $W/wocg.v
run cg0  -DCG -DCG_EN=1\'b0 $SRC 00_TESTBED/GATED_OR.v
run cg1  -DCG $SRC 00_TESTBED/GATED_OR.v
