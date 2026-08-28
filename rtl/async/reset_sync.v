//=====================================================================
// Module      : reset_sync
// Description : Standard "assert async, deassert sync" reset
//               synchronizer. The incoming reset can assert at any
//               time relative to clk (async assert -- no synchronizer
//               needed for that direction, an async reset input on a
//               flop is safe by construction). Deassertion is
//               re-timed through two flops so every flop in this clock
//               domain comes out of reset on the same edge, rather
//               than some seeing the deassertion a fraction of a
//               cycle before others.
//=====================================================================
module reset_sync (
    input  wire clk,
    input  wire async_rst_n,    // possibly-asynchronous active-low reset in
    output reg  sync_rst_n      // active-low reset out, synchronized to clk
);

    reg rff1;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rff1       <= 1'b0;
            sync_rst_n <= 1'b0;
        end else begin
            rff1       <= 1'b1;
            sync_rst_n <= rff1;
        end
    end

endmodule
