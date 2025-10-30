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
    input  logic                                        write_en_main_mem,
    input  logic [DATA_WIDTH - 1 : 0]                   data_in,
    input  logic [DATA_WIDTH*WORDS_PER_BLOCK - 1 : 0]   data_in_main_mem,
    input  logic [ADDRESS_WIDTH - 1 : 0]                mem_add,
    output logic                                        data_ready,
    output logic [DATA_WIDTH - 1 : 0]                   data_out,
    output logic                                        data_ready_main_mem,
    output logic [DATA_WIDTH*WORDS_PER_BLOCK - 1 : 0]   data_out_main_mem 
);

logic [DATA_WIDTH - 1 : 0] data_in_main_mem_packed  [0 : WORDS_PER_BLOCK - 1];
logic [DATA_WIDTH - 1 : 0] data_out_main_mem_packed [0 : WORDS_PER_BLOCK - 1];

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

// Add after your existing reg declarations
reg [SET_WIDTH-1:0]    latched_set;
reg [TAG_WIDTH-1:0]    latched_tag;
reg [OFFSET_WIDTH-1:0] latched_offset;
reg [1:0]              latched_victim;
reg [TAG_WIDTH-1:0]    victim_tag;  

// For write-allocate
reg                    pending_write;
reg [DATA_WIDTH-1:0]   pending_write_data;
reg [OFFSET_WIDTH-1:0] pending_write_offset;

logic[WAY - 1 : 0] HIT;
logic[WAY - 1 : 0] valid;
logic[WAY - 1 : 0] dirty;

typedef enum logic [2 : 0] {
    idle,
    read,
    write,
    read_miss,
    get_victim,
    write_back,
    read_from_main_mem
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
end

always_comb begin
    for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
        data_in_main_mem_packed[i] = data_in_main_mem[i*DATA_WIDTH +: DATA_WIDTH];
    end    
end

always_comb begin
    for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
        data_out_main_mem[i*DATA_WIDTH +: DATA_WIDTH] = data_out_main_mem_packed[i];
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

always @(posedge clk , posedge reset) begin
    if(reset) begin
        state_curr           <= idle;
        data_out             <= 'b0;
        data_ready_main_mem  <= 1'b0;
        latched_set          <= 0;
        latched_tag          <= 0;
        latched_offset       <= 0;
        latched_victim       <= 0;
        victim_tag           <= 0;
        pending_write        <= 0;
        pending_write_data   <= 0;
        pending_write_offset <= 0;

        for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
            data_out_main_mem_packed[i]   <= 'b0;
        end

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
        state_curr <= state_next;
    end 
end

//fsm signals
logic read_true;
logic write_hit_true;
logic write_back_true;
logic read_from_main_mem_true;

logic        write_hit;
logic[1 : 0] write_hit_way;
logic[1 : 0] free_way;

always @(*) begin
    state_next              = state_curr;
    read_true               = 0;
    write_hit_true          = 0;
    write_back_true         = 0;
    read_from_main_mem_true = 0;

    case (state_curr)
        idle: begin
            if(~write_en && data_ready) begin
                state_next = read;
            end else if(write_en) begin
                state_next = write;
            end
        end

        read: begin
                if (|HIT) begin
                    read_true = 1;
                    state_next = idle;        
                end else begin
                    state_next = read_miss;
                end
        end

        write: begin
            write_hit = 0;
            for (integer i = 0; i < WAY; i++) begin
                if(HIT[i] == 1) begin
                    write_hit = 1;
                end
            end

            if (write_hit) begin
                write_hit_true = 1;
                state_next = idle;                
            end
            else if(|HIT == 0) begin //write miss
                write_hit_true = 0;
                if (&valid == 0) begin
                    state_next = idle;
                end
                else begin
                    state_next = get_victim; // write miss and cache full
                end
            end 
        end

        read_miss: begin
            if(&dirty == 1'b1) begin
                state_next = get_victim;
            end else begin
                state_next = read_from_main_mem;
            end
        end

        get_victim: begin
            state_next = write_back;
        end

        write_back: begin
            write_back_true = 1;
            state_next = read_from_main_mem;
        end

        read_from_main_mem: begin
            read_from_main_mem_true = 1;
            if(pending_write) begin
                state_next = idle;
            end else begin
                state_next = read;
            end
        end
    endcase
end

always @(posedge clk) begin
    logic [ADDRESS_WIDTH-1:0] victim_addr;
    logic [ADDRESS_WIDTH-OFFSET_WIDTH-BYTE_OFFSET-1:0] victim_block_addr;
    logic [ADDRESS_WIDTH-OFFSET_WIDTH-BYTE_OFFSET-1:0] block_addr;

    case (state_curr)

    idle: begin
        latched_set    <= set;
        latched_tag    <= tag;
        latched_offset <= offset;
    end

    read: begin
        latched_set    <= set;
        latched_tag    <= tag;
        latched_offset <= offset;
        
        if(read_true) begin
            for (integer i = 0; i < WAY; i++) begin
                if(HIT[i]) begin
                    data_out                  <= CACHE_MEMORY[set][i][offset]; 
                    LRU_COUNTER[set][i]       <= 0;
                    for (integer j = 0; j < WAY; j++) begin
                        if(j != i && VALID[set][j]) begin
                            LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                        end
                    end  
                end
            end 
        end       
    end

    write: begin
        latched_set    <= set;
        latched_tag    <= tag;
        latched_offset <= offset;

        if(write_hit_true) begin
            write_hit_way = -1;
            for (integer i = 0; i < WAY; i++) begin
                if(HIT[i] == 1) begin
                    write_hit_way = i;
                end
            end
            CACHE_MEMORY[set][write_hit_way][offset]         <= data_in; 
            DIRTY[set][write_hit_way]                        <= 1'b1;
            TAG_IN_CACHE_MEMORY[set][write_hit_way]          <= tag;
            VALID[set][write_hit_way]                        <= 1'b1;
            LRU_COUNTER[set][write_hit_way]                  <= 0;
            for (integer j = 0; j < WAY; j++) begin
                if (j != write_hit_way && VALID[set][j]) begin
                    LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                end
            end
        end

        else if(!write_hit_true) begin
            free_way = -1;
            for (integer i = 0; i < WAY; i++) begin
                if(VALID[set][i] == 1'b0 && free_way == -1) begin
                    free_way = i;
                end
            end
            if(free_way != -1) begin
                CACHE_MEMORY[set][free_way][offset]         <= data_in; 
                TAG_IN_CACHE_MEMORY[set][free_way]          <= tag;
                VALID[set][free_way]                        <= 1'b1;
                DIRTY[set][free_way]                        <= 1'b1;
                LRU_COUNTER[set][free_way]                  <= 0;
                for (integer j = 0; j < WAY; j++) begin
                    if (j != free_way && VALID[set][j]) begin
                        LRU_COUNTER[set][j] <= LRU_COUNTER[set][j] + 1;
                    end
                end
            end 
            else begin
                pending_write        <= 1;
                pending_write_data   <= data_in;
                pending_write_offset <= offset;
            end    
        end
    end

    read_miss: begin
        latched_victim     <= get_replacement(latched_set);
        victim_tag <= TAG_IN_CACHE_MEMORY[latched_set][get_replacement(latched_set)];        
    end

    get_victim: begin
        latched_victim     <= get_replacement(latched_set);
        victim_tag <= TAG_IN_CACHE_MEMORY[latched_set][get_replacement(latched_set)];
    end

    write_back: begin
        if(write_back_true) begin
            victim_addr = {victim_tag, latched_set, {OFFSET_WIDTH{1'b0}}, {BYTE_OFFSET{1'b0}}};
            victim_block_addr = victim_addr[ADDRESS_WIDTH-1:OFFSET_WIDTH+BYTE_OFFSET];
                
            for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
                MAIN_MEMORY[victim_block_addr][i] <= CACHE_MEMORY[latched_set][latched_victim][i];
            end
            data_ready_main_mem <= 1'b1;
            VALID[latched_set][latched_victim]  <= 1'b0;
            DIRTY[latched_set][latched_victim]  <= 1'b0;
        end
    end

    read_from_main_mem: begin
        if(read_from_main_mem_true) begin
            block_addr = mem_add[ADDRESS_WIDTH-1:OFFSET_WIDTH+BYTE_OFFSET];

            for (integer i = 0; i < WORDS_PER_BLOCK; i++) begin
                CACHE_MEMORY[latched_set][latched_victim][i] <= MAIN_MEMORY[block_addr][i];
            end
            data_ready_main_mem                      <= 1'b0;

            if(pending_write) begin
                CACHE_MEMORY[latched_set][latched_victim][pending_write_offset] <= pending_write_data;
                DIRTY[latched_set][latched_victim]                              <= 1'b1;
                pending_write                                                   <= 1'b0;
            end 
            else begin
                DIRTY[latched_set][latched_victim]                              <= 1'b0;
            end

            TAG_IN_CACHE_MEMORY[latched_set][latched_victim] <= latched_tag;
            VALID[latched_set][latched_victim]               <= 1'b1;
        end
    end
    endcase
end
endmodule
