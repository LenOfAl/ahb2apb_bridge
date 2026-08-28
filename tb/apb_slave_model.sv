//=====================================================================
// Module      : apb_slave_model
// Description : Behavioral (non-synthesizable) APB slave used only in
//               verification. Backs a small word-addressed memory and
//               lets the testbench control, per access:
//                 - wait_cycles  : extra wait states before PREADY
//                 - inject_error : assert PSLVERR on completion
//               Both knobs are plain ports driven from the testbench.
//
//               PREADY/PRDATA/PSLVERR are all COMBINATIONAL, matching
//               how a real APB peripheral behaves: the response must
//               be valid and stable for the entire cycle in which the
//               bridge samples it. A registered response introduces a
//               one-cycle mismatch against a master that (correctly)
//               samples PREADY/PRDATA/PSLVERR within the same access
//               cycle -- an easy bug to introduce and a good thing for
//               a testbench like this one to be able to catch.
//=====================================================================
module apb_slave_model #(
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 256
)(
    input  wire                   PCLK,
    input  wire                   PRESETn,
    input  wire [31:0]            PADDR,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire [DATA_WIDTH-1:0]  PWDATA,

    input  wire [7:0]             wait_cycles,  // extra wait states before PREADY
    input  wire                   inject_error, // assert PSLVERR on completion

    output wire [DATA_WIDTH-1:0]  PRDATA,
    output wire                   PREADY,
    output wire                   PSLVERR
);

    localparam AW = (MEM_DEPTH <= 1) ? 1 : $clog2(MEM_DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    wire [AW-1:0]        word_addr = PADDR[AW+1:2];

    // Cycles elapsed since this access first asserted PSEL & PENABLE.
    // Resets to 0 whenever not selected, so the very first selected
    // cycle always starts counting from a settled value -- no reliance
    // on "what happened last cycle" at the moment PENABLE first goes
    // high, which is what causes the classic false-ready glitch.
    reg [7:0] cycle_cnt;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            cycle_cnt <= 8'd0;
        end else if (PSEL && PENABLE) begin
            if (!PREADY)
                cycle_cnt <= cycle_cnt + 8'd1;
            else
                cycle_cnt <= 8'd0;   // this access is completing; reset for the next one
        end else begin
            cycle_cnt <= 8'd0;
        end
    end

    assign PREADY  = !(PSEL && PENABLE) ? 1'b1 : (cycle_cnt >= wait_cycles);
    assign PRDATA  = inject_error ? {DATA_WIDTH{1'b0}} : mem[word_addr];
    assign PSLVERR = (PSEL && PENABLE) ? inject_error : 1'b0;

    // Write commits on the cycle PREADY is actually high, using the
    // stable, current-cycle PWDATA/word_addr.
    always @(posedge PCLK) begin
        if (PSEL && PENABLE && PREADY && PWRITE && !inject_error)
            mem[word_addr] <= PWDATA;
    end

endmodule
