module cache_main_mem #(
    parameter MEM_SIZE      = 4096,
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32
) (
    input logic  [ DATA_WIDTH - 1 : 0]   data_in,
    input logic                          write_en,clk,reset,data_received,
    input logic  [ADDRESS_WIDTH - 1 : 0] mem_add,
    output logic [DATA_WIDTH - 1 : 0]    data_out,
    output logic                         data_ready,
    output logic [ADDRESS_WIDTH - 1 : 0] mem_add_read
);

reg [DATA_WIDTH - 1 : 0]    MAIN_MEMORY         [0 : MEM_SIZE - 1];
reg [ADDRESS_WIDTH - 1 : 0] MAIN_MEMORY_ADDRESS [0 : MEM_SIZE - 1];

always @(posedge clk, posedge reset)  begin
    if (reset) begin
        data_out     <= 'b0;
        mem_add_read <= 'b0;
        data_ready   <= 1'b0;
    end else if (~write_en) begin
        data_out     <= MAIN_MEMORY[mem_add];
        mem_add_read <= MAIN_MEMORY_ADDRESS[mem_add];
        data_ready   <= 1'b1;
    end else if (write_en) begin
        MAIN_MEMORY[mem_add]         <= data_in;
        MAIN_MEMORY_ADDRESS[mem_add] <= mem_add;
        data_received                <= 1'b1;
    end
end
    
endmodule