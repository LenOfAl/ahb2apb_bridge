//=====================================================================
// Module      : async_fifo
// Description : Dual-clock asynchronous FIFO for crossing a data path
//               between two unrelated clocks. Classic Cummings-style
//               design: binary + Gray-coded read/write pointers, each
//               pointer synchronized into the OTHER clock domain with
//               a 2-flop synchronizer.
//
//               Depth = 2**ADDR_WIDTH. Read side is first-word-fall-
//               through: rdata is valid combinationally as soon as
//               !rempty, no extra pop-then-wait cycle needed.
//
// Why Gray code, specifically: a synchronizer flop can only safely
// sample a signal that changes ONE BIT at a time. A binary counter
// crossing from 3 (011) to 4 (100) changes all three bits at once; if
// the receiving flop samples mid-transition, unrelated bits can each
// independently resolve high or low and the synchronized value can
// land on ANY of 000-111, not just 3 or 4. Gray code guarantees
// adjacent counts differ by exactly one bit, so a synchronizer that
// catches the pointer mid-update can only ever resolve to the old or
// the new value -- never a bogus code in between. That's what makes
// it safe to synchronize a multi-bit pointer with plain flip-flops
// instead of a full handshake for every single access.
//
// full/empty are deliberately functions of CURRENT (already-registered)
// pointer state only -- never of the live wr_en/rd_en input in the same
// expression. A "look-ahead" formulation (comparing against pointer+1
// combinationally) is a valid and common optimization, but it must then
// be registered before use; comparing it against a live enable in the
// same cycle re-introduces the same "deciding based on its own
// not-yet-committed decision" ambiguity that this design avoids
// everywhere else. Current-state comparison costs at most one cycle of
// pessimism (full/empty can be asserted one cycle earlier than the
// absolute limit) in exchange for being unambiguous to reason about.
//=====================================================================
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 2     // depth = 2**ADDR_WIDTH
)(
    // ---------------- write side (wclk domain) ----------------
    input  wire                   wclk,
    input  wire                   wrst_n,   // already synchronized to wclk
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wdata,
    output wire                   wfull,

    // ---------------- read side (rclk domain) ----------------
    input  wire                   rclk,
    input  wire                   rrst_n,   // already synchronized to rclk
    input  wire                   rd_en,
    output wire [DATA_WIDTH-1:0]  rdata,
    output wire                   rempty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // ------------------------------------------------------------------
    // All declarations up front, before any logic references them.
    // Some tools (VCS included) require declare-before-use within a
    // module rather than treating declarations as hoisted to module
    // scope regardless of textual order -- an earlier draft of this
    // file declared the read-domain pointers (rbin/rgray) after the
    // write-domain synchronizer block that samples them, which Icarus
    // tolerated but VCS correctly rejected ("Identifier not declared
    // yet"). Declaring everything up front avoids relying on any one
    // tool's leniency about ordering.
    // ------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    reg  [ADDR_WIDTH:0] wbin, wgray;      // write domain: binary + Gray pointer (extra MSB disambiguates full vs empty)
    reg  [ADDR_WIDTH:0] rq1_gray, rq2_gray;  // read pointer synchronized into wclk domain

    reg  [ADDR_WIDTH:0] rbin, rgray;      // read domain: binary + Gray pointer
    reg  [ADDR_WIDTH:0] wq1_gray, wq2_gray;  // write pointer synchronized into rclk domain

    // Convert a Gray-coded pointer back to binary. Needed because the
    // pointer must stay Gray-coded through the synchronizer flops (see
    // above), but binary is far easier to compare correctly by hand.
    function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
        integer j;
        begin
            gray2bin[ADDR_WIDTH] = g[ADDR_WIDTH];
            for (j = ADDR_WIDTH-1; j >= 0; j = j - 1)
                gray2bin[j] = gray2bin[j+1] ^ g[j];
        end
    endfunction

    // ---------------- write domain ----------------
    // Deliberately NOT gated by ~wfull: gating a pointer's own "next"
    // value on a flag computed FROM that next value is a combinational
    // loop (wfull -> wbin_next -> wfull) and can hang a simulator
    // outright. Standard contract instead: the pointer advances whenever
    // wr_en is asserted, and it's the CALLER's job never to assert wr_en
    // while wfull is high (exactly like never popping while rempty).
    wire [ADDR_WIDTH:0] wbin_next  = wbin + wr_en;
    wire [ADDR_WIDTH:0] wgray_next = (wbin_next >> 1) ^ wbin_next;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= {(ADDR_WIDTH+1){1'b0}};
            wgray <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
        end
    end

    // 2-flop synchronizer: read pointer (Gray) -> write clock domain
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            rq1_gray <= {(ADDR_WIDTH+1){1'b0}};
            rq2_gray <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            rq1_gray <= rgray;
            rq2_gray <= rq1_gray;
        end
    end

    // Full when the CURRENT write pointer has already lapped the
    // synchronized read pointer by exactly one full trip around the
    // circular buffer: same low address bits, opposite lap (MSB) bit.
    wire [ADDR_WIDTH:0] rbin_sync = gray2bin(rq2_gray);
    assign wfull = (wbin[ADDR_WIDTH]     != rbin_sync[ADDR_WIDTH]) &&
                   (wbin[ADDR_WIDTH-1:0] == rbin_sync[ADDR_WIDTH-1:0]);

    always @(posedge wclk) begin
        if (wr_en && !wfull)
            mem[wbin[ADDR_WIDTH-1:0]] <= wdata;
    end

    // ---------------- read domain ----------------
    wire [ADDR_WIDTH:0] rbin_next  = rbin + rd_en;   // caller must not pop while rempty
    wire [ADDR_WIDTH:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin  <= {(ADDR_WIDTH+1){1'b0}};
            rgray <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
        end
    end

    // 2-flop synchronizer: write pointer (Gray) -> read clock domain
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            wq1_gray <= {(ADDR_WIDTH+1){1'b0}};
            wq2_gray <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            wq1_gray <= wgray;
            wq2_gray <= wq1_gray;
        end
    end

    // Empty when the CURRENT read pointer already matches the
    // synchronized write pointer exactly -- same address, same lap.
    wire [ADDR_WIDTH:0] wbin_sync = gray2bin(wq2_gray);
    assign rempty = (rbin == wbin_sync);
    assign rdata  = mem[rbin[ADDR_WIDTH-1:0]];   // FWFT: valid combinationally whenever !rempty

endmodule
