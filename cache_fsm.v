module cache_fsm #(
    parameter MEM_SIZE        = 4096,
    parameter CACHE_SIZE      = 1024,
    parameter SETS            = 256,
    parameter ADDRESS_WIDTH   = 32,
    parameter DATA_WIDTH      = 32,
    parameter TAG_WIDTH       = 18,
    parameter SET_WIDTH       = 8,
    parameter OFFSET_WIDTH    = 4,
    parameter WAY             = 4,
    parameter BYTE_OFFSET     = $clog2(DATA_WIDTH/8),
    parameter WORDS_PER_BLOCK = 1 << OFFSET_WIDTH
) ( 
    input  logic                                        clk, 
    input  logic                                        write_en,
    input  logic                                        reset,
    input  logic [DATA_WIDTH - 1 : 0]                   data_in,
    input  logic [ADDRESS_WIDTH - 1 : 0]                mem_add,
    output logic                                        data_ready,
    output logic [DATA_WIDTH - 1 : 0]                   data_out
    //output logic                                        data_ready_main_mem
);

localparam ADD             = ADDRESS_WIDTH;
localparam TAG_IN_ADD      = SET_WIDTH + OFFSET_WIDTH + BYTE_OFFSET;
localparam SET_IN_ADD      = OFFSET_WIDTH + BYTE_OFFSET;
localparam BYTE_OFFSET_ADD = BYTE_OFFSET;

wire [TAG_WIDTH - 1 : 0]    tag    = mem_add[ADD - 1 : TAG_IN_ADD];        //tag separation
wire [SET_WIDTH - 1 : 0]    set    = mem_add[TAG_IN_ADD - 1 : SET_IN_ADD]; //set separation
wire [OFFSET_WIDTH - 1 : 0] offset = mem_add[SET_IN_ADD - 1 : BYTE_OFFSET_ADD];//offset separation  

// Internal memory
reg [DATA_WIDTH-1:0] MAIN_MEMORY [0:MEM_SIZE-1][0:WORDS_PER_BLOCK-1];

reg [DATA_WIDTH - 1 : 0] CACHE_MEMORY        [0 : SETS - 1][0 : WAY - 1][0 : WORDS_PER_BLOCK - 1];
reg [TAG_WIDTH - 1 : 0]  TAG_IN_CACHE_MEMORY [0 : SETS - 1][0 : WAY - 1];
reg                      VALID               [0 : SETS - 1][0 : WAY - 1];
reg                      DIRTY               [0 : SETS - 1][0 : WAY - 1];
reg [1 : 0]              LRU_COUNTER         [0 : SETS - 1][0 : WAY - 1];


reg [SET_WIDTH-1:0]    latched_set;
reg [TAG_WIDTH-1:0]    latched_tag;
reg [OFFSET_WIDTH-1:0] latched_offset;
reg [1:0]              latched_victim;
reg [TAG_WIDTH-1:0]    victim_tag;
reg [DATA_WIDTH - 1 : 0] latched_data_in;

// For write-allocate
reg                    pending_write;
reg [DATA_WIDTH-1:0]   pending_write_data;
reg [OFFSET_WIDTH-1:0] pending_write_offset;

logic[WAY - 1 : 0] HIT;
logic[WAY - 1 : 0] valid;
logic[WAY - 1 : 0] dirty;
logic[WAY - 1 : 0] latched_hit;
logic[WAY - 1 : 0] latched_valid;
logic[WAY - 1 : 0] latched_dirty;

typedef enum logic [2 : 0] {
    IDLE,
    READ,
    WRITE,
    READ_MISS,
    GET_VICTIM,
    WRITE_BACK,
    READ_FROM_MAIN_MEM
} state_type;

state_type state_curr, state_next;

always_comb begin
    for (integer i = 0; i < WAY; i++) begin
        HIT[i] = (VALID[set][i] && TAG_IN_CACHE_MEMORY[set][i] == tag);
    end

    for (integer i = 0; i < WAY; i++) begin
        valid[i] = (VALID[set][i]);
        dirty[i] = (DIRTY[set][i]);
    end

    for (integer i = 0; i < WAY; i++) begin
        latched_hit[i]   = (VALID[latched_set][i] && TAG_IN_CACHE_MEMORY[latched_set][i] == latched_tag);
        latched_valid[i] = VALID[latched_set][i];
        latched_dirty[i] = DIRTY[latched_set][i];
    end
end

assign data_ready = |HIT;

function automatic integer get_replacement;
input [SET_WIDTH - 1 : 0] set_index;
    begin
    integer max;
    integer victim;
        max    = -1;
        victim = 0;

        for (integer i = 0; i < WAY; i++) begin
            if (LRU_COUNTER[set_index][i] > max) begin
                max    = LRU_COUNTER[set_index][i];
                victim = i;
            end
        end
        return victim;
    end
endfunction

function automatic integer free_way;
input[SET_WIDTH - 1 : 0] set_index;
    begin
        for (integer i = 0; i < WAY; i++) begin
            if(VALID[set_index][i] == 1'b0) begin
                return i;
            end
        end
    end
endfunction

logic        write_hit;
logic[1 : 0] write_hit_way;

logic [ADDRESS_WIDTH-1:0] victim_addr;
logic [ADDRESS_WIDTH-OFFSET_WIDTH-BYTE_OFFSET-1:0] victim_block_addr;
logic [ADDRESS_WIDTH-OFFSET_WIDTH-BYTE_OFFSET-1:0] block_addr;

always @(posedge clk) begin
    if(reset) begin
        state_curr           <= IDLE;
        data_out             <= 'b0;
        //data_ready_main_mem  <= 1'b0;
        latched_set          <= 0;
        latched_tag          <= 0;
        latched_offset       <= 0;
        latched_victim       <= 0;
        victim_tag           <= 0;
        pending_write        <= 0;
        pending_write_data   <= 0;
        pending_write_offset <= 0;

        for (integer i = 0; i < SETS; i++) begin
            for (integer j = 0; j < WAY; j++) begin
                LRU_COUNTER[i][j]         <= j;
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
    else begin

    case (state_curr)
        IDLE: begin
            latched_set     <= set;
            latched_tag     <= tag;
            latched_offset  <= offset;
            latched_data_in <= data_in;
            pending_write   <= 0;

            if(~write_en) begin
                state_curr <= READ;
            end else if(write_en) begin
                state_curr <= WRITE;
            end
        end

        READ: begin
            if (|latched_hit) begin
                state_curr <= IDLE;
                for (integer i = 0; i < WAY; i++) begin
                    if(latched_hit[i]) begin
                        data_out                  <= CACHE_MEMORY[latched_set][i][latched_offset]; 
                        LRU_COUNTER[latched_set][i]       <= 0;
                        for (integer j = 0; j < WAY; j++) begin
                            if(j != i && VALID[latched_set][j]) begin
                                LRU_COUNTER[latched_set][j] <= LRU_COUNTER[latched_set][j] + 1;
                            end
                        end
                    end  
                end
            end                             
            else begin
                state_curr <= READ_MISS;
            end
        end

        WRITE: begin
            write_hit = 0;
            for (integer i = 0; i < WAY; i++) begin
                if(latched_hit[i] == 1) begin
                    write_hit = 1;
                end
            end

            if (write_hit) begin
                write_hit_way = -1;
                for (integer i = 0; i < WAY; i++) begin
                    if(latched_hit[i] == 1) begin
                        write_hit_way = i;
                    end
                end
                CACHE_MEMORY[latched_set][write_hit_way][latched_offset] <= latched_data_in; 
                DIRTY[latched_set][write_hit_way]                        <= 1'b1;
                TAG_IN_CACHE_MEMORY[latched_set][write_hit_way]          <= latched_tag;
                VALID[latched_set][write_hit_way]                        <= 1'b1;
                LRU_COUNTER[latched_set][write_hit_way]                  <= 0;
                for (integer j = 0; j < WAY; j++) begin
                    if (j != write_hit_way && VALID[latched_set][j]) begin
                        LRU_COUNTER[latched_set][j] <= LRU_COUNTER[latched_set][j] + 1;
                    end
                end
                state_curr <= IDLE;   
            end

            else if(|latched_hit == 0) begin //write miss
                pending_write        <= 1;
                pending_write_data   <= latched_data_in;
                pending_write_offset <= latched_offset;
                if (&latched_valid == 1) begin //all ways valid hence get victim
                    state_curr <= GET_VICTIM;
                end
                else begin
                    state_curr <= READ_MISS;
                end
            end 
        end

        READ_MISS: begin
            if((&latched_valid == 1)) begin //if all ways valid, get victim
                state_curr      <= GET_VICTIM;
                latched_victim  <= get_replacement(latched_set);
                victim_tag      <= TAG_IN_CACHE_MEMORY[latched_set][get_replacement(latched_set)];     
            end else begin //atleast one way is free, no need to write-back
                state_curr     <= READ_FROM_MAIN_MEM;
                latched_victim <= free_way(latched_set); 
                victim_tag     <= TAG_IN_CACHE_MEMORY[latched_set][free_way(latched_set)];
            end
        end

        GET_VICTIM: begin
            if(DIRTY[latched_set][latched_victim]) begin  
                state_curr <= WRITE_BACK;
            end else begin
                state_curr <= READ_FROM_MAIN_MEM;  // Clean victim skip write-back
            end  
        end

        WRITE_BACK: begin
            state_curr <= READ_FROM_MAIN_MEM;
                
            for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
                MAIN_MEMORY[victim_addr[11 : 0]][i] <= CACHE_MEMORY[latched_set][latched_victim][i];
            end
            //data_ready_main_mem <= 1'b1;
            VALID[latched_set][latched_victim]  <= 1'b0;
            DIRTY[latched_set][latched_victim]  <= 1'b0;
        end

        READ_FROM_MAIN_MEM: begin

            for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
                CACHE_MEMORY[latched_set][latched_victim][i] <= MAIN_MEMORY[block_addr[11 : 0]][i];
            end
            //data_ready_main_mem                      <= 1'b0;

            if(pending_write) begin
                CACHE_MEMORY[latched_set][latched_victim][pending_write_offset] <= pending_write_data;
                DIRTY[latched_set][latched_victim]                              <= 1'b1;
            end 
            else begin
                DIRTY[latched_set][latched_victim]                              <= 1'b0;
            end

            TAG_IN_CACHE_MEMORY[latched_set][latched_victim] <= latched_tag;
            VALID[latched_set][latched_victim]               <= 1'b1;
            LRU_COUNTER[latched_set][latched_victim] <= 0;
            for (integer j = 0; j < WAY; j++) begin
                if(j != latched_victim && VALID[latched_set][j]) begin
                    LRU_COUNTER[latched_set][j] <= LRU_COUNTER[latched_set][j] + 1;
                end
            end
            if(pending_write) begin
                state_curr <= IDLE;
            end else begin
                state_curr <= READ;
            end
        end
    endcase
    end 
end

assign victim_addr = {victim_tag, latched_set};
assign block_addr = {latched_tag, latched_set};

endmodule
