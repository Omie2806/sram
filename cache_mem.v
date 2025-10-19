module cache_mem #(
    parameter CACHE_SIZE    = 1024,
    parameter SETS          = 256,
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 18,
    parameter SET_WIDTH     = 8,
    parameter OFFSET_WIDTH  = 6,
    parameter WAY           = 4

) ( 
    input  logic                        clk, 
    input  logic                        write_en,
    input  logic                        reset,
    input  logic                        write_en_main_mem,
    input  logic [DATA_WIDTH - 1 : 0]   data_in_main_mem, data_in,
    input  logic [ADDRESS_WIDTH - 1 : 0]mem_add,
    output logic                        data_ready,
    output logic [DATA_WIDTH - 1 : 0]   data_out,
    output logic                        data_ready, data_ready_main_mem,
    output logic [DATA_WIDTH - 1 : 0]   data_out_main_mem
);

localparam WORDS_PER_BLOCK = 2**OFFSET_WIDTH;
localparam ADD             = ADDRESS_WIDTH;
localparam TAG_IN_ADD      = SET_WIDTH + OFFSET_WIDTH;
localparam SET_IN_ADD      = OFFSET_WIDTH;

wire [TAG_WIDTH - 1 : 0]    tag    = mem_add[ADD - 1 : TAG_IN_ADD];        //tag separation
wire [SET_WIDTH - 1 : 0]    set    = mem_add[TAG_IN_ADD - 1 : SET_IN_ADD]; //set separation
wire [OFFSET_WIDTH - 1 : 0] offset = mem_add[SET_IN_ADD - 1 : 0];          //offset separation   

reg [DATA_WIDTH - 1 : 0] CACHE_MEMORY        [0 : SETS - 1][0 : WAY - 1][0 : WORDS_PER_BLOCK - 1];
reg [TAG_WIDTH - 1 : 0]  TAG_IN_CACHE_MEMORY [0 : SETS - 1][0 : WAY - 1];
reg                      VALID               [0 : SETS - 1][0 : WAY - 1];
reg                      DIRTY               [0 : SETS - 1][0 : WAY - 1];
reg [1 : 0]              LRU_COUNTER         [0 : SETS - 1][0 : WAY - 1];

logic[WAY - 1 : 0]       HIT;

always_comb begin
    for (integer i = 0; i < WAY; i++) begin
        HIT[i] = (VALID[set][i] && TAG_IN_CACHE_MEMORY[set][i] == tag);
    end
end

assign data_ready = |HIT;

function integer get_replacement();
    integer max = -1;
    integer victim = 0;

    for (integer i = 0; i < WAY; i++) begin
        if (LRU_COUNTER[set][i] > max) begin
            max    = LRU_COUNTER[set][i];
            victim = i;
        end
    end
    return victim;
endfunction

always @(posedge clk , posedge reset) begin
    integer victim = 0;

    if (reset) begin
        data_out            <= 'b0;
        data_ready_main_mem <= 1'b0;
        data_out_main_mem   <= 'b0';

        for (integer i = 0; i < SETS; i++) begin
            for (integer j = 0; j < WAY; j++) begin
                LRU_COUNTER[i][j]         <= 'b0;
                TAG_IN_CACHE_MEMORY[i][j] <= 'b0;
                VALID[i][j]               <= 'b0;
                DIRTY[i][j]               <= 'b0;               
            end
        end
    end 
    //read to cpu
    if (~write_en && data_ready) begin 
        for (integer i = 0; i < WAY; i++) begin
            if (HIT[i]) begin
                data_out                  <= CACHE_MEMORY[set][i][offset]; 
            end
        end
    end

    //write from cpu
    else if (write_en)  begin 

        if(&VALID[set] == 1'b0) begin
            for (integer i = 0; i < WAY; i++) begin
                if (VALID[set][i] == 1'b0) begin //writing if memory is empty or data is not valid
                    CACHE_MEMORY[set][i][offset]         <= data_in; 
                    TAG_IN_CACHE_MEMORY[set][i]          <= tag;
                    VALID[set][i]                        <= 1'b1;
                    DIRTY[set][i]                        <= 1'b1;
                    LRU_COUNTER[set][i]                  <= 0;
                for (integer j = 0; j < WAY; j++) begin
                    if (j != i) begin
                        LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                    end
                end
                end 
            end 
        end else begin // when all blocks are valid, use lru to replace
            victim                     = get_replacement();
            data_out_main_mem         <= CACHE_MEMORY[set][victim];
            CACHE_MEMORY[set][victim] <= data_in;
        end
    end
    //write to main mem when reading 
    else if ((|DIRTY[set] == 1'b1) && (|HIT == 1'b0)) begin
        victim               = get_replacement();
        data_out_main_mem   <= CACHE_MEMORY[set][victim];
        data_ready_main_mem <= 1'b1;
        DIRTY[set][victim]  <= 1'b0;
        VALID[set][victim]  <= 1'b0;

    end
    //read from main memory
    else if (write_en_main_mem) begin
        victim                     = get_replacement();
        CACHE_MEMORY[set][victim] <= data_in_main_mem;
        DIRTY[set][victim]        <= 1'b1;
        VALID[set][victim]        <= 1'b1;
        LRU_COUNTER[set][victim]  <= 0;
        for (integer j = 0; j < WAY; j++) begin
            if (j != victim) begin
                LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
            end
        end
    end

end

endmodule
