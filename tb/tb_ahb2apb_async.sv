//=====================================================================
// Module      : tb_ahb2apb_async
// Description : Self-checking testbench for ahb2apb_bridge_async,
//               structurally the same directed + randomized suite as
//               tb_ahb2apb.sv (the synchronous bridge), but HCLK and
//               PCLK are driven at deliberately unrelated periods with
//               an offset start, specifically to exercise the CDC
//               boundary rather than let a lucky clock ratio hide a
//               synchronization bug.
//=====================================================================
`timescale 1ns/1ps

module tb_ahb2apb_async;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam NUM_SLAVES = 4;

    // Deliberately unrelated clock periods (no common simple ratio) and
    // an offset start, so the two domains are never edge-aligned.
    localparam HCLK_PERIOD = 10.0;   // ns
    localparam PCLK_PERIOD = 4.7;    // ns

    localparam [1:0] HTRANS_IDLE   = 2'b00;
    localparam [1:0] HTRANS_BUSY   = 2'b01;
    localparam [1:0] HTRANS_NONSEQ = 2'b10;
    localparam [1:0] HTRANS_SEQ    = 2'b11;

    localparam [1:0] RESP_OKAY  = 2'b00;
    localparam [1:0] RESP_ERROR = 2'b01;

    // ---------------- DUT signals ----------------
    reg                    HCLK;
    reg                    HRESETn;
    reg                    HSEL;
    reg  [ADDR_WIDTH-1:0]  HADDR;
    reg  [1:0]             HTRANS;
    reg                    HWRITE;
    reg  [2:0]             HSIZE;
    reg  [DATA_WIDTH-1:0]  HWDATA;
    wire                   HREADY;
    wire [DATA_WIDTH-1:0]  HRDATA;
    wire                   HREADYOUT;
    wire [1:0]             HRESP;

    reg                    PCLK;
    reg                    PRESETn;
    wire [ADDR_WIDTH-1:0]  PADDR;
    wire [NUM_SLAVES-1:0]  PSEL;
    wire                   PENABLE;
    wire                   PWRITE;
    wire [DATA_WIDTH-1:0]  PWDATA;

    // Per-slave arrays, and the scalar mux feeding the DUT -- identical
    // approach to the synchronous testbench.
    wire [DATA_WIDTH-1:0]  slave_prdata  [NUM_SLAVES-1:0];
    wire                   slave_pready  [NUM_SLAVES-1:0];
    wire                   slave_pslverr [NUM_SLAVES-1:0];

    reg  [DATA_WIDTH-1:0]  prdata_muxed;
    reg                     pready_muxed;
    reg                     pslverr_muxed;
    integer                 k;
    always @(*) begin
        prdata_muxed  = {DATA_WIDTH{1'b0}};
        pready_muxed  = 1'b1;
        pslverr_muxed = 1'b0;
        for (k = 0; k < NUM_SLAVES; k = k + 1) begin
            if (PSEL[k]) begin
                prdata_muxed  = slave_prdata[k];
                pready_muxed  = slave_pready[k];
                pslverr_muxed = slave_pslverr[k];
            end
        end
    end

    assign HREADY = HREADYOUT;

    int unsigned errors    = 0;
    int unsigned txn_count = 0;

    // ---------------- DUT instantiation ----------------
    ahb2apb_bridge_async #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_SLAVES (NUM_SLAVES),
        .FIFO_ADDR_WIDTH (2)
    ) dut (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSEL      (HSEL),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HRDATA    (HRDATA),
        .HREADYOUT (HREADYOUT),
        .HRESP     (HRESP),
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .PADDR     (PADDR),
        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PWDATA    (PWDATA),
        .PRDATA    (prdata_muxed),
        .PREADY    (pready_muxed),
        .PSLVERR   (pslverr_muxed)
    );

    // ---------------- APB slave models ----------------
    reg  [7:0]             wait_cycles_arr  [0:NUM_SLAVES-1];
    reg                     inject_error_arr [0:NUM_SLAVES-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : g_slave
            apb_slave_model #(
                .DATA_WIDTH (DATA_WIDTH),
                .MEM_DEPTH  (256)
            ) u_slave (
                .PCLK         (PCLK),
                .PRESETn      (PRESETn),
                .PADDR        (PADDR),
                .PSEL         (PSEL[gi]),
                .PENABLE      (PENABLE),
                .PWRITE       (PWRITE),
                .PWDATA       (PWDATA),
                .wait_cycles  (wait_cycles_arr[gi]),
                .inject_error (inject_error_arr[gi]),
                .PRDATA       (slave_prdata[gi]),
                .PREADY       (slave_pready[gi]),
                .PSLVERR      (slave_pslverr[gi])
            );
        end
    endgenerate

    // ---------------- Clocks: unrelated periods, offset start ----------------
    initial HCLK = 1'b0;
    always #(HCLK_PERIOD/2) HCLK = ~HCLK;

    initial begin
        PCLK = 1'b0;
        #1.3;  // phase offset so the domains never line up on a shared edge
        forever #(PCLK_PERIOD/2) PCLK = ~PCLK;
    end

    // ---------------- Reference memory / scoreboard ----------------
    reg [DATA_WIDTH-1:0] expected_mem [0:(NUM_SLAVES*256)-1];
    reg                   mem_written  [0:(NUM_SLAVES*256)-1];

    function automatic int flat_index(input [ADDR_WIDTH-1:0] addr);
        int slave_idx, word_idx;
        slave_idx  = addr[ADDR_WIDTH-1 -: 2];
        word_idx   = (addr[9:2]) % 256;
        flat_index = slave_idx * 256 + word_idx;
    endfunction

    // ---------------- Bus driver tasks ----------------
    task automatic apply_reset();
        HRESETn = 1'b0;
        PRESETn = 1'b0;
        HSEL    = 1'b0;
        HADDR   = {ADDR_WIDTH{1'b0}};
        HTRANS  = HTRANS_IDLE;
        HWRITE  = 1'b0;
        HSIZE   = 3'b010;
        HWDATA  = {DATA_WIDTH{1'b0}};
        for (int s = 0; s < NUM_SLAVES; s++) begin
            wait_cycles_arr[s]  = 8'd0;
            inject_error_arr[s] = 1'b0;
        end
        repeat (6) @(posedge HCLK);
        HRESETn = 1'b1;
        PRESETn = 1'b1;
        repeat (6) @(posedge HCLK);   // let both reset synchronizers settle
    endtask

    task automatic drive_idle_cycle();
        @(negedge HCLK);
        HSEL   = 1'b1;
        HTRANS = HTRANS_IDLE;
        @(posedge HCLK);
        @(negedge HCLK);
        HSEL = 1'b0;
    endtask

    task automatic drive_busy_cycle();
        @(negedge HCLK);
        HSEL   = 1'b1;
        HTRANS = HTRANS_BUSY;
        @(posedge HCLK);
        @(negedge HCLK);
        HSEL = 1'b0;
    endtask

    // Same negedge-based polling discipline as the synchronous testbench:
    // sample HREADYOUT/HRDATA/HRESP at a settled mid-cycle point, and take
    // one extra edge after detecting completion before returning, so a
    // subsequent set_wait_cycles()/set_inject_error() call can never land
    // on a transaction that's still (even nominally) in flight.
    task automatic ahb_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [2:0]            size
    );
        @(negedge HCLK);
        while (HREADYOUT !== 1'b1) @(negedge HCLK);

        HSEL   = 1'b1;
        HADDR  = addr;
        HTRANS = HTRANS_NONSEQ;
        HWRITE = 1'b1;
        HSIZE  = size;
        @(negedge HCLK);

        HTRANS = HTRANS_IDLE;
        HWDATA = data;
        @(negedge HCLK);

        while (HREADYOUT !== 1'b1) @(negedge HCLK);
        @(negedge HCLK);
        HSEL = 1'b0;
        txn_count = txn_count + 1;
    endtask

    task automatic ahb_read(
        input  [ADDR_WIDTH-1:0] addr,
        input  [2:0]             size,
        output [DATA_WIDTH-1:0]  data,
        output [1:0]              resp
    );
        @(negedge HCLK);
        while (HREADYOUT !== 1'b1) @(negedge HCLK);

        HSEL   = 1'b1;
        HADDR  = addr;
        HTRANS = HTRANS_NONSEQ;
        HWRITE = 1'b0;
        HSIZE  = size;
        @(negedge HCLK);

        HTRANS = HTRANS_IDLE;
        @(negedge HCLK);

        while (HREADYOUT !== 1'b1) @(negedge HCLK);
        data = HRDATA;
        resp = HRESP;
        @(negedge HCLK);
        HSEL = 1'b0;
        txn_count = txn_count + 1;
    endtask

    task automatic set_wait_cycles(input int w);
        for (int s = 0; s < NUM_SLAVES; s++)
            wait_cycles_arr[s] = w[7:0];
    endtask

    task automatic set_inject_error(input bit e);
        for (int s = 0; s < NUM_SLAVES; s++)
            inject_error_arr[s] = e;
    endtask

    task automatic do_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        ahb_write(addr, data, 3'b010);
        if (!inject_error_arr[addr[ADDR_WIDTH-1 -: 2]]) begin
            expected_mem[flat_index(addr)] = data;
            mem_written[flat_index(addr)]  = 1'b1;
        end
    endtask

    task automatic do_read_check(input [ADDR_WIDTH-1:0] addr);
        reg [DATA_WIDTH-1:0] rdata;
        reg [1:0]             rresp;
        ahb_read(addr, 3'b010, rdata, rresp);
        if (mem_written[flat_index(addr)] && rresp == RESP_OKAY) begin
            if (rdata !== expected_mem[flat_index(addr)]) begin
                errors = errors + 1;
                $error("[SCOREBOARD] addr=%08h expected=%08h got=%08h",
                        addr, expected_mem[flat_index(addr)], rdata);
            end
        end
    endtask

    task automatic random_transaction();
        reg [1:0]              slave_idx;
        reg [ADDR_WIDTH-1:0]   addr;
        reg [DATA_WIDTH-1:0]   data;
        bit                     do_write_txn;
        int                      w;

        slave_idx    = $urandom_range(0, NUM_SLAVES-1);
        addr         = (slave_idx << 30) | ($urandom_range(0, 255) << 2);
        data         = $urandom;
        do_write_txn = $urandom_range(0, 1);
        w            = $urandom_range(0, 3);   // keep wait states modest; CDC latency already adds plenty

        set_wait_cycles(w);
        set_inject_error(1'b0);

        if (do_write_txn)
            do_write(addr, data);
        else
            do_read_check(addr);
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        apply_reset();

        drive_idle_cycle();
        drive_busy_cycle();

        for (int s = 0; s < NUM_SLAVES; s++) begin
            reg [ADDR_WIDTH-1:0] a;
            a = {s[1:0], 30'h0000_0010};
            set_wait_cycles(0);
            do_write(a, 32'hA5A5_0000 + s);
            do_read_check(a);
        end

        for (int w = 0; w <= 3; w++) begin
            reg [ADDR_WIDTH-1:0] a;
            a = {2'b01, 30'h0000_0020} + (w << 2);
            set_wait_cycles(w);
            do_write(a, 32'h1000_0000 + w);
            do_read_check(a);
        end
        set_wait_cycles(0);

        ahb_write({2'b10, 30'h0000_0030}, 32'h0000_00FF, 3'b000);
        ahb_write({2'b10, 30'h0000_0034}, 32'h0000_FFFF, 3'b001);

        begin
            reg [DATA_WIDTH-1:0] rdata;
            reg [1:0]             rresp;
            set_wait_cycles(1);
            set_inject_error(1'b1);
            ahb_write({2'b11, 30'h0000_0040}, 32'hDEAD_BEEF, 3'b010);
            ahb_read({2'b11, 30'h0000_0040}, 3'b010, rdata, rresp);
            if (rresp != RESP_ERROR) begin
                errors = errors + 1;
                $error("[SCOREBOARD] expected HRESP=ERROR on injected-error access, got %0d", rresp);
            end
            set_inject_error(1'b0);
        end

        repeat (150) random_transaction();

        repeat (20) @(posedge HCLK);

        $display("=================================================");
        $display(" TEST SUMMARY: %0d transactions, %0d errors", txn_count, errors);
        $display(" HCLK period=%0.2fns  PCLK period=%0.2fns  (independent clocks)", HCLK_PERIOD, PCLK_PERIOD);
        $display("=================================================");
        if (errors == 0)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");

        $finish;
    end

    initial begin
        #5000000;
        $display("[TIMEOUT] Testbench did not finish in time");
        $finish;
    end

endmodule
