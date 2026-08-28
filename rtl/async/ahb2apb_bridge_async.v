//=====================================================================
// Module      : ahb2apb_bridge_async
// Description : AHB-Lite to APB bridge for the case where HCLK and
//               PCLK are genuinely independent clocks (different PLLs,
//               unrelated frequency and phase -- not just a known
//               integer divide of one another).
//
//               Architecture: the single shared apb_fsm from the
//               synchronous bridge is split into two independent FSMs,
//               one per clock domain, connected by a pair of
//               asynchronous FIFOs (see async_fifo.v for why Gray-code
//               pointers + 2-flop synchronizers, and what that buys
//               you). ahb_req_fsm (HCLK) packages each accepted AHB
//               transfer into a request and pushes it into the TX
//               FIFO; apb_req_fsm (PCLK) pops it, runs the normal APB
//               SETUP/ACCESS handshake against the peripheral, and
//               pushes the response into the RX FIFO; ahb_req_fsm pops
//               that and completes the AHB transfer.
//
//               Externally this looks identical to the synchronous
//               bridge -- same AHB-Lite slave port, same scalar
//               PRDATA/PREADY/PSLVERR APB master port muxed by the
//               caller across NUM_SLAVES peripherals. The only
//               observable difference is timing: a transfer now takes
//               a data-dependent number of HCLK cycles (address+data
//               phase, then however long the FIFO round trip and the
//               APB access itself take) instead of the synchronous
//               bridge's fixed minimum of 3.
//
//               Both incoming resets are treated as possibly-async and
//               locally re-synchronized to their own clock domain.
//=====================================================================
module ahb2apb_bridge_async #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_SLAVES = 4,
    parameter FIFO_ADDR_WIDTH = 2      // FIFO depth = 2**FIFO_ADDR_WIDTH; protocol is
                                        // single-outstanding, depth 4 is ample headroom
)(
    // ---------------- AHB-Lite slave port (HCLK domain) ----------------
    input  wire                   HCLK,
    input  wire                   HRESETn,
    input  wire                   HSEL,
    input  wire [ADDR_WIDTH-1:0]  HADDR,
    input  wire [1:0]             HTRANS,
    input  wire                   HWRITE,
    input  wire [2:0]             HSIZE,
    input  wire [DATA_WIDTH-1:0]  HWDATA,
    input  wire                   HREADY,
    output wire [DATA_WIDTH-1:0]  HRDATA,
    output wire                   HREADYOUT,
    output wire [1:0]             HRESP,

    // ---------------- APB master port (PCLK domain) ----------------
    input  wire                   PCLK,
    input  wire                   PRESETn,
    output wire [ADDR_WIDTH-1:0]  PADDR,
    output wire [NUM_SLAVES-1:0]  PSEL,
    output wire                   PENABLE,
    output wire                   PWRITE,
    output wire [DATA_WIDTH-1:0]  PWDATA,
    input  wire [DATA_WIDTH-1:0]  PRDATA,
    input  wire                   PREADY,
    input  wire                   PSLVERR
);

    localparam REQ_WIDTH  = ADDR_WIDTH + 1 + 3 + DATA_WIDTH;  // {addr, write, size, wdata}
    localparam RESP_WIDTH = 1 + DATA_WIDTH;                    // {slverr, rdata}

    // ---------------- local reset synchronizers ----------------
    wire hresetn_sync, presetn_sync;

    reset_sync u_hreset_sync (.clk(HCLK), .async_rst_n(HRESETn), .sync_rst_n(hresetn_sync));
    reset_sync u_preset_sync (.clk(PCLK), .async_rst_n(PRESETn), .sync_rst_n(presetn_sync));

    // ---------------- HCLK side ----------------
    wire [ADDR_WIDTH-1:0] haddr_reg;
    wire                   hwrite_reg;
    wire [2:0]             hsize_reg;
    wire                   xfer_valid;

    ahb_slave_if #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_ahb_slave_if (
        .HCLK       (HCLK),
        .HRESETn    (hresetn_sync),
        .HSEL       (HSEL),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HREADY     (HREADY),
        .haddr_reg  (haddr_reg),
        .hwrite_reg (hwrite_reg),
        .hsize_reg  (hsize_reg),
        .xfer_valid (xfer_valid)
    );

    wire                    tx_wr_en;
    wire [REQ_WIDTH-1:0]    tx_wdata;
    wire                    tx_wfull;
    wire                    rx_rd_en;
    wire [RESP_WIDTH-1:0]   rx_rdata;
    wire                    rx_rempty;

    ahb_req_fsm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ahb_req_fsm (
        .HCLK        (HCLK),
        .HRESETn     (hresetn_sync),
        .xfer_valid  (xfer_valid),
        .haddr_reg   (haddr_reg),
        .hwrite_reg  (hwrite_reg),
        .hsize_reg   (hsize_reg),
        .HWDATA      (HWDATA),
        .tx_wr_en    (tx_wr_en),
        .tx_wdata    (tx_wdata),
        .tx_wfull    (tx_wfull),
        .rx_rd_en    (rx_rd_en),
        .rx_rdata    (rx_rdata),
        .rx_rempty   (rx_rempty),
        .HREADYOUT   (HREADYOUT),
        .HRDATA      (HRDATA),
        .HRESP       (HRESP)
    );

    // ---------------- PCLK side ----------------
    wire                    tx_rd_en;
    wire [REQ_WIDTH-1:0]    tx_rdata;
    wire                    tx_rempty;
    wire                    rx_wr_en;
    wire [RESP_WIDTH-1:0]   rx_wdata;
    wire                    rx_wfull;

    wire [ADDR_WIDTH-1:0]   paddr_int;
    wire                    psel_enable;
    wire [NUM_SLAVES-1:0]   psel_dec;

    apb_req_fsm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_apb_req_fsm (
        .PCLK        (PCLK),
        .PRESETn     (presetn_sync),
        .tx_rd_en    (tx_rd_en),
        .tx_rdata    (tx_rdata),
        .tx_rempty   (tx_rempty),
        .rx_wr_en    (rx_wr_en),
        .rx_wdata    (rx_wdata),
        .rx_wfull    (rx_wfull),
        .PADDR       (paddr_int),
        .PWRITE      (PWRITE),
        .PWDATA      (PWDATA),
        .PENABLE     (PENABLE),
        .psel_enable (psel_enable),
        .PRDATA      (PRDATA),
        .PREADY      (PREADY),
        .PSLVERR     (PSLVERR)
    );

    assign PADDR = paddr_int;

    addr_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .NUM_SLAVES (NUM_SLAVES)
    ) u_addr_decoder (
        .haddr_reg (paddr_int),
        .psel_dec  (psel_dec)
    );

    assign PSEL = psel_dec & {NUM_SLAVES{psel_enable}};

    // ---------------- the two async FIFOs ----------------
    async_fifo #(
        .DATA_WIDTH (REQ_WIDTH),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_tx_fifo (
        .wclk   (HCLK),  .wrst_n (hresetn_sync), .wr_en (tx_wr_en), .wdata (tx_wdata), .wfull (tx_wfull),
        .rclk   (PCLK),  .rrst_n (presetn_sync), .rd_en (tx_rd_en), .rdata (tx_rdata), .rempty (tx_rempty)
    );

    async_fifo #(
        .DATA_WIDTH (RESP_WIDTH),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_rx_fifo (
        .wclk   (PCLK),  .wrst_n (presetn_sync), .wr_en (rx_wr_en), .wdata (rx_wdata), .wfull (rx_wfull),
        .rclk   (HCLK),  .rrst_n (hresetn_sync), .rd_en (rx_rd_en), .rdata (rx_rdata), .rempty (rx_rempty)
    );

endmodule
