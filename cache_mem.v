module cache_mem #(
    parameter CACHE_SIZE    = 1024,
    parameter SETS          = 256,
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 18,
    parameter SET_WIDTH     = 8,
    parameter OFFSET_WIDTH  = 6
) ( 
    input  logic                        clk, 
    input  logic                        write_en,
    input  logic [ADDRESS_WIDTH - 1 : 0]mem_add,
    output logic                        data_ready,
    output logic [DATA_WIDTH - 1 : 0]   data_out
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
endmodule