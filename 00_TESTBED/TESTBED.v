`timescale 1ns/10ps
// Usage: +define+CG  -> design has cg_en port (LAB8_DESIGN.v), cg_en = `CG_EN (default 1)
//        (no define) -> LAB8_DESIGN_wocg.v
module TESTBED;
wire clk, rst_n, in_valid, out_valid;
wire [7:0]  in_data;
wire [11:0] out_data;
`ifdef CG
  `ifndef CG_EN
    `define CG_EN 1'b1
  `endif
  wire cg_en = `CG_EN;
  LAB8_DESIGN u_LAB8_DESIGN(.clk(clk), .rst_n(rst_n), .cg_en(cg_en), .in_valid(in_valid), .in_data(in_data),
                            .out_valid(out_valid), .out_data(out_data));
`else
  LAB8_DESIGN u_LAB8_DESIGN(.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_data(in_data),
                            .out_valid(out_valid), .out_data(out_data));
`endif
PATTERN u_PATTERN(.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_data(in_data),
                  .out_valid(out_valid), .out_data(out_data));
`ifdef VCD
initial begin $dumpfile(`VCD); $dumpvars(0, u_LAB8_DESIGN); end
`endif
endmodule
