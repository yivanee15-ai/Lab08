#!/usr/bin/env python3
"""Derive LAB8_DESIGN_wocg.v from the clock-gated source: only the clock gating part changes.
   - every GATED_OR instance   ->  assign <gated clock> = clk;
   - the cg_en port is removed
"""
import re, sys
src = open(sys.argv[1]).read()
pat = re.compile(r"GATED_OR\s+\w+\s*\(\s*\.CLOCK\(clk\)\s*,\s*\.SLEEP_CTRL\(.*\)\s*,\s*\.RST_N\(rst_n\)\s*,\s*\.CLOCK_GATED\((\w+)\)\s*\);")
out, n = pat.subn(lambda m: f"assign {m.group(1)} = clk;", src)
out, m = re.subn(r"^\s*input\s+cg_en,\n", "", out, flags=re.M)
assert n > 0 and m == 1 and "GATED_OR" not in out and "cg_en" not in out, (n, m)
open(sys.argv[2], "w").write(out)
print(f"{sys.argv[2]}: replaced {n} gating instances")
