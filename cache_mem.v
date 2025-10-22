module cache_mem #(
    parameter CACHE_SIZE      = 1024,
    parameter SETS            = 256,
    parameter ADDRESS_WIDTH   = 32,
    parameter DATA_WIDTH      = 32,
    parameter TAG_WIDTH       = 18,
    parameter SET_WIDTH       = 8,
    parameter OFFSET_WIDTH    = 6,
    parameter WORDS_PER_BLOCK = 2**OFFSET_WIDTH,
    parameter WAY             = 4

) ( 
    input  logic                        clk, 
    input  logic                        write_en,
    input  logic                        reset,
    input  logic                        write_en_main_mem,
    input  logic [DATA_WIDTH - 1 : 0]   data_in,
    input  logic [DATA_WIDTH - 1 : 0]   data_in_main_mem [0 : WORDS_PER_BLOCK - 1],
    input  logic [ADDRESS_WIDTH - 1 : 0]mem_add,
    output logic                        data_ready,
    output logic [DATA_WIDTH - 1 : 0]   data_out,
    output logic                        data_ready_main_mem,
    output logic [DATA_WIDTH - 1 : 0]   data_out_main_mem [0 : WORDS_PER_BLOCK - 1]
);


localparam ADD             = ADDRESS_WIDTH;
localparam TAG_IN_ADD      = SET_WIDTH + OFFSET_WIDTH;
localparam SET_IN_ADD      = OFFSET_WIDTH;

wire [TAG_WIDTH - 1 : 0]    tag    = mem_add[ADD - 1 : TAG_IN_ADD];        //tag separation
wire [SET_WIDTH - 1 : 0]    set    = mem_add[TAG_IN_ADD - 1 : SET_IN_ADD]; //set separation
wire [OFFSET_WIDTH - 1 : 0] offset = mem_add[SET_IN_ADD - 1 : 2];          //offset separation   

reg [DATA_WIDTH - 1 : 0] CACHE_MEMORY        [0 : SETS - 1][0 : WAY - 1][0 : WORDS_PER_BLOCK - 1];
reg [TAG_WIDTH - 1 : 0]  TAG_IN_CACHE_MEMORY [0 : SETS - 1][0 : WAY - 1];
reg                      VALID               [0 : SETS - 1][0 : WAY - 1];
reg                      DIRTY               [0 : SETS - 1][0 : WAY - 1];
reg [3 : 0]              LRU_COUNTER         [0 : SETS - 1][0 : WAY - 1];

logic[WAY - 1 : 0]       HIT;

logic[WAY - 1 : 0] valid;
logic[WAY - 1 : 0] dirty;

always_comb begin
    for (integer i = 0; i < WAY; i++) begin
        HIT[i] = (VALID[set][i] && TAG_IN_CACHE_MEMORY[set][i] == tag);
    end

    for (integer i = 0; i < WAY; i++) begin
        valid[i] = (VALID[set][i]);
        dirty[i] = (DIRTY[set][i]);
    end

end

assign data_ready = |HIT;

function automatic integer get_replacement();
    begin
    integer max;
    integer victim;
        max    = -1;
        victim = 0;
        for (integer i = 0; i < WAY; i++) begin
            if (LRU_COUNTER[set][i] > max) begin
                max    = LRU_COUNTER[set][i];
                victim = i;
            end
        end
        return victim;
    end
endfunction

integer victim;
integer write_hit;
integer write_hit_way;

always @(posedge clk , posedge reset) begin
    victim = 0;
    write_hit = 0;
    write_hit_way = 0;

    if (reset) begin
        data_out            <= 'b0;
        data_ready_main_mem <= 1'b0;

        for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
            data_out_main_mem[i]   <= 'b0;
        end

        for (integer i = 0; i < SETS; i++) begin
            for (integer j = 0; j < WAY; j++) begin
                LRU_COUNTER[i][j]         <= 'b0;
                TAG_IN_CACHE_MEMORY[i][j] <= 'b0;
                VALID[i][j]               <= 'b0;
                DIRTY[i][j]               <= 'b0;              
            end
        end

        for (integer i = 0; i < SETS; i++) begin
            for (integer j = 0; j < WAY; j++) begin
                for (integer k = 0; k < WORDS_PER_BLOCK; k++) begin
                    CACHE_MEMORY[i][j][k] <= 'b0;
                end
            end
        end
    end 
    //read to cpu
    else if (~write_en && data_ready) begin 
        data_ready_main_mem  <= 1'b0;
        for (integer i = 0; i < WAY; i++) begin
            if (HIT[i]) begin
                data_out                  <= CACHE_MEMORY[set][i][offset]; 
                LRU_COUNTER[set][i]       <= 0;
                for (integer j = 0; j < WAY; j++) begin
                    if(j != i) begin
                        LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                    end
                end
            end
        end
    end

    //write from cpu
    else if (write_en)  begin 
        data_ready_main_mem <= 1'b0;
        for (integer i = 0; i < WAY; i++) begin
            if(HIT[i] == 1) begin
                write_hit = 1;
                write_hit_way = i;
            end
        end
        
        if (write_hit) begin
            CACHE_MEMORY[set][write_hit_way][offset]         <= data_in; 
            TAG_IN_CACHE_MEMORY[set][write_hit_way]          <= tag;
            VALID[set][write_hit_way]                        <= 1'b1;
            DIRTY[set][write_hit_way]                        <= 1'b1;
            LRU_COUNTER[set][write_hit_way]                  <= 0;
            for (integer j = 0; j < WAY; j++) begin
                if (j != write_hit_way) begin
                    LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                end
            end
        end

        else if(&valid == 1'b0) begin
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
            victim                            = get_replacement();

            if (DIRTY[set][victim]) begin
                for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
                    data_out_main_mem[i] <= CACHE_MEMORY[set][victim][i];
                end
                data_ready_main_mem <= 1'b1;
            end

            CACHE_MEMORY[set][victim][offset] <= data_in;
            TAG_IN_CACHE_MEMORY[set][victim]  <= tag;
            VALID[set][victim]                <= 1'b1;
            DIRTY[set][victim]                <= 1'b1;
            LRU_COUNTER[set][victim]          <= 0;
                for (integer j = 0; j < WAY; j++) begin
                    if (j != victim) begin
                        LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                    end
                end            
        end
    end
    //write to main mem when reading 
    else if (~write_en && (|HIT == 1'b0) && ~write_en_main_mem) begin
        victim               = get_replacement();
        if(DIRTY[set][victim]) begin
            for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
                data_out_main_mem[i]                <= CACHE_MEMORY[set][victim][i];
            end        
            data_ready_main_mem <= 1'b1;
            DIRTY[set][victim]  <= 1'b0;
        end
        VALID[set][victim]  <= 1'b0;
    end
    //read from main memory
    else if (write_en_main_mem) begin
        victim                     = get_replacement();
        for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
            CACHE_MEMORY[set][victim][i] <= data_in_main_mem[i];
        end
        data_ready_main_mem              <= 1'b0;
        TAG_IN_CACHE_MEMORY[set][victim] <= tag;
        DIRTY[set][victim]               <= 1'b0;
        VALID[set][victim]               <= 1'b1;
        LRU_COUNTER[set][victim]         <= 0;
        for (integer j = 0; j < WAY; j++) begin
            if (j != victim) begin
                LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
            end
        end
    end else begin
        data_ready_main_mem <= 1'b0;
    end

end

endmodule
