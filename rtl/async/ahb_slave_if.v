//=====================================================================
// Module      : ahb_slave_if
// Description : AHB-Lite slave-side interface for the AHB2APB bridge.
//               Detects a valid address-phase transfer (HSEL, HREADY,
//               NONSEQ/SEQ) and registers HADDR/HWRITE/HSIZE for use
//               by the address decoder and APB FSM on the following
//               cycle, consistent with the AHB address/data pipeline.
//=====================================================================
module ahb_slave_if #(
    parameter ADDR_WIDTH = 32
)(
    input  wire                  HCLK,
    input  wire                  HRESETn,
    input  wire                  HSEL,
    input  wire [ADDR_WIDTH-1:0] HADDR,
    input  wire [1:0]            HTRANS,
    input  wire                  HWRITE,
    input  wire [2:0]            HSIZE,
    input  wire                  HREADY,

    output reg  [ADDR_WIDTH-1:0] haddr_reg,
    output reg                   hwrite_reg,
    output reg  [2:0]            hsize_reg,
    output wire                  xfer_valid   // pulses when a new address-phase transfer is accepted
);

    // NONSEQ (2'b10) or SEQ (2'b11) qualified by HSEL & HREADY = valid address phase.
    // IDLE (2'b00) and BUSY (2'b01) are intentionally not decoded as transfers.
    assign xfer_valid = HSEL & HREADY & HTRANS[1];

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            haddr_reg  <= {ADDR_WIDTH{1'b0}};
            hwrite_reg <= 1'b0;
            hsize_reg  <= 3'b000;
        end else if (xfer_valid) begin
            haddr_reg  <= HADDR;
            hwrite_reg <= HWRITE;
            hsize_reg  <= HSIZE;
        end
    end

endmodule
