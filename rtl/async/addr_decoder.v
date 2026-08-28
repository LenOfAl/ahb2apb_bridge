//=====================================================================
// Module      : addr_decoder
// Description : Combinationally decodes the registered AHB address
//               into a one-hot select for up to NUM_SLAVES APB
//               peripherals. The top SEL_BITS of the address select
//               the slave region. Adjust ADDR_WIDTH/NUM_SLAVES (or
//               replace with explicit base/size compares) to match
//               your real memory map.
//=====================================================================
module addr_decoder #(
    parameter ADDR_WIDTH = 32,
    parameter NUM_SLAVES = 4
)(
    input  wire [ADDR_WIDTH-1:0]  haddr_reg,
    output reg  [NUM_SLAVES-1:0]  psel_dec
);

    localparam SEL_BITS = (NUM_SLAVES <= 1) ? 1 : $clog2(NUM_SLAVES);
    wire [SEL_BITS-1:0] sel_idx = haddr_reg[ADDR_WIDTH-1 -: SEL_BITS];

    integer i;
    always @(*) begin
        psel_dec = {NUM_SLAVES{1'b0}};
        for (i = 0; i < NUM_SLAVES; i = i + 1) begin
            if (i == sel_idx)
                psel_dec[i] = 1'b1;
        end
    end

endmodule
