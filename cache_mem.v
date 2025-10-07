module cache_mem #(
    parameter CACHE_SIZE    = 1024,
    parameter SETS          = 256,
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 18,
    parameter SET_WIDTH     = 8,
    parameter OFFSET_WIDTH  = 6
) ( 
    input  logic                        clk, reset,
    input  logic                        write_en,write_en_main_mem,
    input  logic [DATA_WIDTH - 1 : 0]   data_in_main_mem,data_in,
    input  logic [ADDRESS_WIDTH - 1 : 0]mem_add,
    output logic                        data_ready,data_ready_main_mem,
    output logic [DATA_WIDTH - 1 : 0]   data_out_main_mem, data_out
);

localparam BLOCKS         = CACHE_SIZE/SETS;

localparam ADD           = ADDRESS_WIDTH;
localparam TAG_IN_ADD    = SET_WIDTH + OFFSET_WIDTH;
localparam SET_IN_ADD    = OFFSET_WIDTH;

wire [TAG_WIDTH - 1 : 0]    tag    = mem_add[ADD - 1 : TAG_IN_ADD];        //tag separation
wire [SET_WIDTH - 1 : 0]    set    = mem_add[TAG_IN_ADD - 1 : SET_IN_ADD]; //set separation
wire [OFFSET_WIDTH - 1 : 0] offset = mem_add[SET_IN_ADD - 1 : 0];          //offset separation   

reg [DATA_WIDTH - 1 : 0] CACHE_MEMORY        [0 : SETS - 1][0 : BLOCKS - 1];
reg [TAG_WIDTH - 1 : 0]  TAG_IN_CACHE_MEMORY [0 : SETS - 1][0 : BLOCKS - 1];
reg                      VALID               [0 : SETS - 1][0 : BLOCKS - 1];
reg                      DIRTY               [0 : SETS - 1][0 : BLOCKS - 1];

wire hit = (VALID[set][offset] && TAG_IN_CACHE_MEMORY[set][offset] == tag);
assign data_ready = hit;

always @(posedge clk , posedge reset) begin
    if (reset) begin
        data_out            <= 'b0;
        data_ready_main_mem <= 1'b0;
        data_ready          <= 1'b0;
        data_out            <= 'b0;
        data_out_main_mem   <= 'b0';
    end 

    //read to cpu
    if (~write_en && hit) begin 
            data_out                  <= CACHE_MEMORY[set][offset]; 
        end
    //write from cpu
    else if (write_en)  begin 
            CACHE_MEMORY[set][offset]                 <= data_in; 
            TAG_IN_CACHE_MEMORY[set][offset]          <= tag;
            VALID[set][offset]                        <= 1'b1;
            DIRTY[set][offset]                        <= 1'b1;
        end
    //write to main mem
    else if (DIRTY[set][offset] == 1'b1 && ~hit) begin
        data_out_main_mem   <= CACHE_MEMORY[set][offset];
        data_ready_main_mem <= 1'b1;
        DIRTY[set][offset]  <= 1'b0;
        VALID[set][offset]  <= 1'b0;
    end
    //read from main mem
    else if (write_en_main_mem) begin
        CACHE_MEMORY[set][offset] <= data_in_main_mem;
        DIRTY[set][offset]        <= 1'b1;
        VALID[set][offset]        <= 1'b1;
        data_ready                <= 1'b1;
    end
end
endmodule