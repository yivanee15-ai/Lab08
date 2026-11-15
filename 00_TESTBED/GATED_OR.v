// Behavioural model of the clock gating cell (latch + OR), same interface as the TA cell.
module GATED_OR(
    input  CLOCK,
    input  SLEEP_CTRL,
    input  RST_N,
    output CLOCK_GATED
);
reg latch_or_sleep;
always @(*) begin
    if (!RST_N)     latch_or_sleep = 1'b0;
    else if (CLOCK) latch_or_sleep = SLEEP_CTRL;
end
assign CLOCK_GATED = CLOCK | latch_or_sleep;
endmodule
