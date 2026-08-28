//=====================================================================
// Module      : ahb_req_fsm
// Description : HCLK-domain half of the asynchronous bridge. Replaces
//               apb_fsm's role from the synchronous design, but instead
//               of driving the APB peripheral directly, it packages a
//               request and hands it across the clock boundary through
//               an async_fifo, then waits for the response to come back
//               through a second async_fifo.
//
//               From the AHB master's point of view this is protocol-
//               identical to the synchronous bridge: HREADYOUT drops
//               the cycle after a transfer is accepted and comes back
//               the cycle HRDATA/HRESP are valid. The only externally
//               visible difference is that the round trip can now take
//               an unpredictable number of HCLK cycles (it depends on
//               PCLK's rate and the synchronizer latency), instead of
//               the fixed minimum of the synchronous version.
//=====================================================================
module ahb_req_fsm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                            HCLK,
    input  wire                            HRESETn,   // already synchronized to HCLK

    input  wire                            xfer_valid,
    input  wire [ADDR_WIDTH-1:0]           haddr_reg,
    input  wire                            hwrite_reg,
    input  wire [2:0]                      hsize_reg,
    input  wire [DATA_WIDTH-1:0]           HWDATA,

    // TX FIFO (request, HCLK -> PCLK), write side
    output reg                             tx_wr_en,
    output reg  [ADDR_WIDTH+DATA_WIDTH+3:0] tx_wdata,   // {addr, write, size, wdata}
    input  wire                            tx_wfull,

    // RX FIFO (response, PCLK -> HCLK), read side
    output reg                             rx_rd_en,
    input  wire [DATA_WIDTH:0]             rx_rdata,    // {slverr, rdata}
    input  wire                            rx_rempty,

    output reg                             HREADYOUT,
    output reg  [DATA_WIDTH-1:0]           HRDATA,
    output reg  [1:0]                      HRESP
);

    localparam [1:0] IDLE      = 2'b00;
    localparam [1:0] CAPTURE   = 2'b01;   // mirrors the sync bridge's SETUP: grab HWDATA, push request
    localparam [1:0] WAIT_RESP = 2'b10;   // wait for the response FIFO

    localparam [1:0] RESP_OKAY  = 2'b00;
    localparam [1:0] RESP_ERROR = 2'b01;

    reg [1:0] state, next_state;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) state <= IDLE;
        else          state <= next_state;
    end

    always @(*) begin
        case (state)
            IDLE:      next_state = xfer_valid ? CAPTURE : IDLE;
            CAPTURE:   next_state = (!tx_wfull) ? WAIT_RESP : CAPTURE;  // stall if TX fifo momentarily full
            WAIT_RESP: next_state = (!rx_rempty) ? IDLE : WAIT_RESP;
            default:   next_state = IDLE;
        endcase
    end

    always @(*) begin
        tx_wr_en  = 1'b0;
        tx_wdata  = {(ADDR_WIDTH+DATA_WIDTH+4){1'b0}};
        rx_rd_en  = 1'b0;
        HREADYOUT = 1'b1;
        HRDATA    = {DATA_WIDTH{1'b0}};
        HRESP     = RESP_OKAY;

        case (state)
            IDLE: begin
                HREADYOUT = 1'b1;
            end

            CAPTURE: begin
                HREADYOUT = 1'b0;
                // Combinational request packet, exactly like the sync
                // bridge's data_mux capturing HWDATA one cycle behind
                // the address phase -- just pushed into a FIFO instead
                // of a plain register.
                tx_wdata = {haddr_reg, hwrite_reg, hsize_reg, HWDATA};
                tx_wr_en = !tx_wfull;
            end

            WAIT_RESP: begin
                HREADYOUT = 1'b0;
                if (!rx_rempty) begin
                    rx_rd_en  = 1'b1;
                    HREADYOUT = 1'b1;
                    HRDATA    = rx_rdata[DATA_WIDTH-1:0];
                    HRESP     = rx_rdata[DATA_WIDTH] ? RESP_ERROR : RESP_OKAY;
                end
            end

            default: ;
        endcase
    end

endmodule
