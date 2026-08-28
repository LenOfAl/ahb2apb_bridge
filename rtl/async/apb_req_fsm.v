//=====================================================================
// Module      : apb_req_fsm
// Description : PCLK-domain half of the asynchronous bridge. Pops a
//               request from the TX FIFO, runs the normal APB
//               SETUP -> ACCESS sequence against the peripheral
//               (structurally identical to the synchronous bridge's
//               apb_fsm), then pushes the response into the RX FIFO.
//               A separate PUSH state decouples the peripheral
//               handshake from the FIFO handshake, so PENABLE/PSEL are
//               always released the cycle after PREADY, even in the
//               (here, essentially unreachable given the single-
//               outstanding protocol) case where the RX FIFO is
//               momentarily full.
//=====================================================================
module apb_req_fsm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                             PCLK,
    input  wire                             PRESETn,   // already synchronized to PCLK

    // TX FIFO (request, HCLK -> PCLK), read side
    output reg                              tx_rd_en,
    input  wire [ADDR_WIDTH+DATA_WIDTH+3:0] tx_rdata,   // {addr, write, size, wdata}
    input  wire                             tx_rempty,

    // RX FIFO (response, PCLK -> HCLK), write side
    output reg                              rx_wr_en,
    output reg  [DATA_WIDTH:0]              rx_wdata,   // {slverr, rdata}
    input  wire                             rx_wfull,

    // APB peripheral port
    output reg  [ADDR_WIDTH-1:0]            PADDR,
    output reg                              PWRITE,
    output reg  [DATA_WIDTH-1:0]            PWDATA,
    output wire                             PENABLE,
    output wire                             psel_enable,   // qualifies addr_decoder's PSEL externally
    input  wire [DATA_WIDTH-1:0]            PRDATA,
    input  wire                             PREADY,
    input  wire                             PSLVERR
);

    localparam [1:0] IDLE  = 2'b00;
    localparam [1:0] SETUP = 2'b01;
    localparam [1:0] ACCESS= 2'b10;
    localparam [1:0] PUSH  = 2'b11;

    reg [1:0] state, next_state;
    reg [DATA_WIDTH-1:0] rdata_cap;
    reg                   slverr_cap;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) state <= IDLE;
        else          state <= next_state;
    end

    always @(*) begin
        case (state)
            IDLE:    next_state = (!tx_rempty) ? SETUP : IDLE;
            SETUP:   next_state = ACCESS;
            ACCESS:  next_state = PREADY ? PUSH : ACCESS;
            PUSH:    next_state = (!rx_wfull) ? IDLE : PUSH;
            default: next_state = IDLE;
        endcase
    end

    // Latch the popped request when leaving IDLE so it stays stable for
    // the whole SETUP/ACCESS sequence, exactly like haddr_reg/hwrite_reg
    // in the synchronous bridge.
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PADDR  <= {ADDR_WIDTH{1'b0}};
            PWRITE <= 1'b0;
            PWDATA <= {DATA_WIDTH{1'b0}};
        end else if (state == IDLE && !tx_rempty) begin
            PADDR  <= tx_rdata[ADDR_WIDTH+DATA_WIDTH+3 -: ADDR_WIDTH];
            PWRITE <= tx_rdata[DATA_WIDTH+3];
            PWDATA <= tx_rdata[DATA_WIDTH-1:0];
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rdata_cap  <= {DATA_WIDTH{1'b0}};
            slverr_cap <= 1'b0;
        end else if (state == ACCESS && PREADY) begin
            rdata_cap  <= PRDATA;
            slverr_cap <= PSLVERR;
        end
    end

    assign PENABLE     = (state == ACCESS);
    assign psel_enable = (state == SETUP) || (state == ACCESS);

    always @(*) begin
        tx_rd_en = (state == IDLE) && !tx_rempty;
        rx_wr_en = 1'b0;
        rx_wdata = {slverr_cap, rdata_cap};
        if (state == PUSH)
            rx_wr_en = !rx_wfull;
    end

endmodule
