#!/usr/bin/env python3
"""Toggle-count power proxy on the mapped netlist (see scripts/eval.sh).
Energy per toggle of a net (pJ, 1.8V) =
    0.5*C*V^2            C = fanout pin caps + wire
  + driver internal      comb cell ~ area, flop Q toggle
  + clock-pin internal   for every flop / gating-latch clock pin on the net
usage: power.py <name> <workdir> [-v]     (-v : per-phase profile and hottest nets, cg netlist)
"""
import json, re, sys
name, W = sys.argv[1], sys.argv[2]
VERB = "-v" in sys.argv
import os
FOCUS = tuple(int(x) for x in os.environ["FOCUS"].split(",")) if "FOCUS" in os.environ else None
TF = {}
TAB = json.load(open("eval/gtab.json"))
area = {k_: v["area"] for k_, v in TAB["cells"].items()}
VV, WIRE, E_CLKPIN, E_Q, K_COMB, CYCLE = 1.8 * 1.8, 0.003, 0.05, 0.15, 0.0012, 15.0
OUTS = ("Y", "Q", "CLOCK_GATED")
def pcap(ty, p):
    if p == "C": return TAB["clkcap"]
    if p == "CLOCK": return TAB["gate_clkcap"]
    if p in ("R", "RST_N"): return 0.0
    return TAB["cells"][ty]["cap"]

def analyse(mode):
    nl = json.load(open(f"{W}/net_{mode}.json"))["modules"]["LAB8_DESIGN"]
    wnet, wclk, wq, wcomb, load = {}, {}, {}, {}, {}
    tot_area, cnt = 0.0, {}
    for c in nl["cells"].values():
        ty = c["type"]; tot_area += area[ty]; cnt[ty] = cnt.get(ty, 0) + 1
        for p, bits in c["connections"].items():
            b = bits[0]
            if not isinstance(b, int): continue
            if p in OUTS:
                if ty.startswith("G_DFF"): wq[b] = E_Q
                elif ty == "GATED_OR":     wcomb[b] = K_COMB * 32
                else:                      wcomb[b] = K_COMB * area[ty]
            else:
                load[b] = load.get(b, 0.0) + pcap(ty, p) + WIRE
                if p in ("C", "CLOCK"): wclk[b] = wclk.get(b, 0.0) + E_CLKPIN
    for b, cap in load.items(): wnet[b] = 0.5 * cap * VV
    nb, nm = {}, {}
    for n_, d in nl["netnames"].items():
        for i, b in enumerate(d["bits"]):
            if isinstance(b, int):
                nb.setdefault(n_.lstrip("\\"), {})[i] = b
                if b not in nm or nm[b].startswith("zn"): nm[b] = f"{n_}[{i}]"
    # ---- VCD ----
    ids, scope = {}, []
    T, prof, state = {}, {}, {"k": 0, "bwd": 0, "run": 0}
    TF.clear()
    f = open(f"{W}/g_{'cg1' if mode == 'cg' else 'wocg'}.vcd")
    for line in f:
        if line.startswith("$scope"): scope.append(line.split()[2])
        elif line.startswith("$upscope"): scope.pop()
        elif line.startswith("$var"):
            p = line.split()
            if len(scope) == 2 and scope[1] == "u_LAB8_DESIGN" and p[4].lstrip("\\") in nb:
                ids.setdefault(p[3], []).append(p[4].lstrip("\\"))
        elif line.startswith("$enddefinitions"): break
    last, t = {}, 0
    def hit(b, n=1):
        T[b] = T.get(b, 0) + n
        if VERB:
            e = wnet.get(b, 0) + wclk.get(b, 0) + wq.get(b, 0) + wcomb.get(b, 0)
            key = (state["bwd"], state["k"] >> 4 if state["run"] else -1)
            prof[key] = prof.get(key, 0.0) + e * n
            if key == FOCUS: TF[b] = TF.get(b, 0) + n
    for line in f:
        c = line[0]
        if c == "#": t = int(line[1:]); continue
        if c in "01xz": v, i = c, line[1:].strip()
        elif c == "b": v, i = line[1:].split()
        else: continue
        if i not in ids: continue
        o = last.get(i); last[i] = v
        for nme in ids[i]:
            if nme in state and "x" not in v: state[nme] = int(v, 2)
        if o is None: continue
        n = max(len(o), len(v))
        a = o.rjust(n, "0" if o[0] in "01" else o[0]); bb = v.rjust(n, "0" if v[0] in "01" else v[0])
        for kk in range(n):
            if a[kk] != bb[kk] and a[kk] in "01" and bb[kk] in "01":
                for nme in ids[i]:
                    b = nb[nme].get(n - 1 - kk)
                    if b is not None: hit(b)
                    break
    cyc = t / 100.0 / CYCLE
    E = lambda w: sum(w[b] * T.get(b, 0) for b in w) / cyc
    r = dict(area=tot_area, ff=sum(v for k_, v in cnt.items() if k_.startswith("G_DFF")), gates=cnt.get("GATED_OR", 0),
             mux=cnt.get("G_MUX", 0), comb_area=sum(area[k_] * v for k_, v in cnt.items() if not k_.startswith("G_DFF") and k_ != "GATED_OR"), net=E(wnet), clk=E(wclk), q=E(wq), comb=E(wcomb))
    r["p"] = r["net"] + r["clk"] + r["q"] + r["comb"]
    if VERB:
        print(f"  -- {mode}: energy share by (task, phase k>>4)   [-1 = idle/task cycle]")
        tot = sum(prof.values())
        for bw in (0, 1):
            print("     task", bw, " ".join(f"{ph}:{100 * prof.get((bw, ph), 0) / tot:4.1f}%" for ph in range(-1, 8)))
        if FOCUS and mode == "cg":
            ew = lambda b: wnet.get(b, 0) + wcomb.get(b, 0) + wq.get(b, 0) + wclk.get(b, 0)
            print(f"     FOCUS {FOCUS}: total {sum(ew(b) * TF[b] for b in TF):.0f} pJ over all patterns; hottest nets:")
            grp = {}
            for b in TF:
                g_ = re.sub(r"\[\d+\]$", "", nm.get(b, "?")); g_ = "zn*" if g_.startswith("zn") else g_
                grp[g_] = grp.get(g_, 0) + ew(b) * TF[b]
            for g_, v in sorted(grp.items(), key=lambda x: -x[1])[:8]: print(f"        {g_:20s} {v:8.0f}")
            drv = {}
            for cn_, c_ in nl["cells"].items():
                for p_, bits in c_["connections"].items():
                    if p_ in OUTS and isinstance(bits[0], int): drv[bits[0]] = c_
            def cone(b, d=0):
                c_ = drv.get(b)
                if c_ is None or d > 3 or not nm.get(b, "zn").startswith("zn"): return nm.get(b, str(b))
                return c_["type"][2:] + "(" + ",".join(cone(x[0], d + 1) if isinstance(x[0], int) else str(x[0]) for p_, x in sorted(c_["connections"].items()) if p_ not in OUTS) + ")"
            for b in sorted(TF, key=lambda b: -ew(b) * TF[b])[:14]:
                if nm.get(b, "zn").startswith("zn"): print(f"        {ew(b) * TF[b]:7.0f} fo-cap {load.get(b, 0):.2f} tog {TF[b]:6d}  {cone(b)[:150]}")
        top = sorted(T, key=lambda b: -(wnet.get(b, 0) + wcomb.get(b, 0) + wq.get(b, 0) + wclk.get(b, 0)) * T[b])[:int(__import__("os").environ.get("TOPN","14"))]
        for b in top:
            print(f"     {nm.get(b, b):22s} tog/cyc {T[b] / cyc:5.2f}  cap {load.get(b, 0):.3f}  E/cyc {(wnet.get(b, 0) + wcomb.get(b, 0) + wq.get(b, 0) + wclk.get(b, 0)) * T[b] / cyc:.2f}")
    return r

def delay(mode):
    d = re.findall(r"Longest topological path in LAB8_DESIGN \(length=(\d+)\)", open(f"{W}/syn_{mode}.log").read())
    return int(d[-1]) if d else -1

r = {m: analyse(m) for m in ("wocg", "cg")}
c, w = r["cg"], r["wocg"]
print(f"== {name}")
print(f"  area(cg) {c['area']:.0f}  [ff {c['ff']}, gating cells {c['gates']}, mux2 {c['mux']}]   area(wocg) {w['area']:.0f}   comb area {c['comb_area']:.0f}   logic depth {delay('cg')} gates")
for m in ("wocg", "cg"):
    x = r[m]
    print(f"  energy/cycle {m:4s} {x['p']:7.2f} pJ  (net {x['net']:.2f}  clk-pin {x['clk']:.2f}  ff-q {x['q']:.2f}  comb {x['comb']:.2f})")
print(f"  gating saves {100 * (1 - c['p'] / w['p']):.1f}%    P^2*A (cg, arbitrary units) = {c['p'] ** 2 * c['area'] / 1e9:.2f}")
json.dump(r, open(f"{W}/proxy.json", "w"), indent=1)
