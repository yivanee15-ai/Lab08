`timescale 1ns/10ps
// Lab08 Coupling Network self-made pattern.
//  - self-contained: with no input.txt in the run directory it generates `PATTERN_NUMBER random
//    patterns (first 12 are corner cases) and checks them with the built-in Verilog golden model
//  - if input.txt / output.txt (golden/golden.py) exist, they are used instead and the Python
//    answers are cross-checked against the built-in model
//  - checks: reset values, out_data==0 while out_valid==0, no in/out valid overlap,
//            latency <= 200, out_valid high for exactly 32 consecutive cycles, data.
`ifndef PATTERN_NUMBER
  `define PATTERN_NUMBER 1000
`endif
`ifndef SEED_NUMBER
  `define SEED_NUMBER 69
`endif
`ifndef CYCLE_TIME
  `define CYCLE_TIME 15.0
`endif
module PATTERN(
    output reg        clk,
    output reg        rst_n,
    output reg        in_valid,
    output reg [7:0]  in_data,
    input             out_valid,
    input      [11:0] out_data
);
real CYCLE = `CYCLE_TIME;
integer use_file, kind;
integer PATNUM, fin, fout, rc, i_pat, i, j, k, t, lat, total_lat, max_lat, seed;
integer inbuf [0:96];
integer gold_file [0:31];
integer gold_calc [0:31];
integer A[0:15], B[0:15], F1[0:15], H1[0:15], F2[0:15], H2[0:15];
integer X[0:15], Y[0:15], MA[0:15], MB[0:15], accx, accy;
reg task_num;

initial clk = 0;
always #(CYCLE/2.0) clk = ~clk;

// ---------------- protocol checkers ----------------
always @(negedge clk) begin
    if (rst_n === 1'b1 && out_valid === 1'b0 && out_data !== 12'd0) begin
        $display("SPEC VIOLATION: out_data should be 0 when out_valid is low  (t=%0t)", $time); $finish;
    end
end
always @(*) begin
    if (in_valid === 1'b1 && out_valid === 1'b1) begin
        $display("SPEC VIOLATION: out_valid overlaps in_valid  (t=%0t)", $time); $finish;
    end
end

// ---------------- independent golden (Verilog) ----------------
task calc_xy; // X = (F x M) % 15 + 1 ; Y = (H x M) % 256 ; sel: 0 -> M = MA, 1 -> M = MB ; fh: 0 -> F1/H1, 1 -> F2/H2
    input sel; input fh;
    integer r, c, q, m, f, h;
    begin
        for (r = 0; r < 4; r = r + 1) for (c = 0; c < 4; c = c + 1) begin
            accx = 0; accy = 0;
            for (q = 0; q < 4; q = q + 1) begin
                m = sel ? MB[4*q+c] : MA[4*q+c];
                f = fh  ? F2[4*r+q] : F1[4*r+q];
                h = fh  ? H2[4*r+q] : H1[4*r+q];
                accx = accx + f * m; accy = accy + h * m;
            end
            X[4*r+c] = accx % 15 + 1; Y[4*r+c] = accy % 256;
        end
    end
endtask

task calc_gold;
    integer e;
    begin
        if (task_num == 1'b0) begin
            for (e = 0; e < 16; e = e + 1) MA[e] = A[e];
            calc_xy(0, 0);
            for (e = 0; e < 16; e = e + 1) MB[e] = (X[e] * B[e]) ^ Y[e];
            calc_xy(1, 1);
            for (e = 0; e < 16; e = e + 1) begin
                gold_calc[e]      = (X[e] * A[e]) ^ Y[e];
                gold_calc[16 + e] = MB[e];
            end
        end else begin
            for (e = 0; e < 16; e = e + 1) MB[e] = B[e];
            calc_xy(1, 1);
            for (e = 0; e < 16; e = e + 1) MA[e] = (A[e] ^ Y[e]) / X[e];
            calc_xy(0, 0);
            for (e = 0; e < 16; e = e + 1) begin
                gold_calc[e]      = MA[e];
                gold_calc[16 + e] = (B[e] ^ Y[e]) / X[e];
            end
        end
    end
endtask

// ---------------- main ----------------
initial begin
    seed = `SEED_NUMBER;
    fin  = $fopen("input.txt", "r");
    fout = $fopen("output.txt", "r");
    use_file = (fin != 0 && fout != 0);
    if (use_file) rc = $fscanf(fin, "%d", PATNUM);
    else begin PATNUM = `PATTERN_NUMBER; $display("input.txt not found: using %0d internally generated patterns", PATNUM); end
`ifdef PATLIMIT
    if (PATNUM > `PATLIMIT) PATNUM = `PATLIMIT;
`endif
    total_lat = 0; max_lat = 0;
    rst_n = 1; in_valid = 0; in_data = 8'bx;
    force clk = 0;
    #(CYCLE * 0.5) rst_n = 0;
    #(CYCLE * 2.0);
    if (out_valid !== 1'b0 || out_data !== 12'd0) begin
        $display("SPEC VIOLATION: outputs must be 0 after reset"); $finish;
    end
    #(CYCLE * 1.0) rst_n = 1;
    #(CYCLE * 1.0) release clk;
    repeat (3) @(negedge clk);

    for (i_pat = 0; i_pat < PATNUM; i_pat = i_pat + 1) begin
        if (use_file) begin
            for (i = 0; i < 97; i = i + 1) rc = $fscanf(fin, "%d", inbuf[i]);
            for (i = 0; i < 32; i = i + 1) rc = $fscanf(fout, "%d", gold_file[i]);
        end else begin
            // corner cases first (both tasks): 0 all zero, 1 all max, 2 F = 0, 3 H = 0, 4 A max / B zero, 5 A zero / B max
            kind = (i_pat < 12) ? i_pat / 2 : 99;
            inbuf[0] = (i_pat < 12) ? i_pat % 2 : {$random(seed)} % 2;
            for (i = 1; i < 97; i = i + 1) begin
                inbuf[i] = (i < 33) ? {$random(seed)} % 256 : {$random(seed)} % 16;
                if (kind == 0) inbuf[i] = 0;
                if (kind == 1) inbuf[i] = (i < 33) ? 255 : 15;
                if (kind == 2 && ((i >= 33 && i < 49) || (i >= 65 && i < 81))) inbuf[i] = 0;
                if (kind == 3 && ((i >= 49 && i < 65) || i >= 81)) inbuf[i] = 0;
                if (kind == 4 && i < 33) inbuf[i] = (i < 17) ? 255 : 0;
                if (kind == 5 && i < 33) inbuf[i] = (i < 17) ? 0 : 255;
            end
        end
        task_num = inbuf[0];
        for (i = 0; i < 16; i = i + 1) begin
            A[i]  = inbuf[1 + i];  B[i]  = inbuf[17 + i]; F1[i] = inbuf[33 + i];
            H1[i] = inbuf[49 + i]; F2[i] = inbuf[65 + i]; H2[i] = inbuf[81 + i];
        end
        calc_gold;
        for (i = 0; i < 32; i = i + 1)
            if (use_file && gold_calc[i] !== gold_file[i]) begin
                $display("GOLDEN MISMATCH (python vs verilog) pattern %0d idx %0d: %0d vs %0d", i_pat, i, gold_file[i], gold_calc[i]);
                $finish;
            end
        // ---- drive 97 cycles ----
        for (i = 0; i < 97; i = i + 1) begin
            in_valid = 1'b1;
            if (i == 0)      in_data = {7'bx, inbuf[0][0]};          // task: only bit 0 is meaningful
            else if (i < 33) in_data = inbuf[i][7:0];
            else             in_data = {4'bx, inbuf[i][3:0]};        // F/H: only bits [3:0] are meaningful
            @(negedge clk);
        end
        in_valid = 1'b0; in_data = 8'bx;
        // ---- wait for out_valid ----
        lat = 0;
        while (out_valid !== 1'b1) begin
            lat = lat + 1;
            if (lat > 200) begin $display("SPEC VIOLATION: latency over 200 cycles (pattern %0d)", i_pat); $finish; end
            @(negedge clk);
        end
        total_lat = total_lat + lat; if (lat > max_lat) max_lat = lat;
        // ---- check 32 cycles ----
        for (i = 0; i < 32; i = i + 1) begin
            if (out_valid !== 1'b1) begin
                $display("SPEC VIOLATION: out_valid must stay high for 32 cycles (pattern %0d, cycle %0d)", i_pat, i); $finish;
            end
            if (out_data !== gold_calc[i][11:0]) begin
                $display("WRONG ANSWER: pattern %0d task %0d out #%0d (%s[%0d][%0d]) golden=%0d yours=%0d",
                         i_pat, task_num, i, (i < 16) ? "OUT_A" : "OUT_B", (i % 16) / 4, i % 4, gold_calc[i], out_data);
                $finish;
            end
            @(negedge clk);
        end
        if (out_valid !== 1'b0) begin
            $display("SPEC VIOLATION: out_valid high for more than 32 cycles (pattern %0d)", i_pat); $finish;
        end
        // ---- 2~5 cycles gap: next in_valid rises 2~5 negedges after out_valid fell ----
        t = 1 + ({$random(seed)} % 4);
        repeat (t) @(negedge clk);
    end
    $display("ALL %0d PATTERNS OK   total latency = %0d cycles, max latency = %0d", PATNUM, total_lat, max_lat);
    $finish;
end
endmodule
