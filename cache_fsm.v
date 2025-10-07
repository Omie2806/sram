module cache_fsm #(
    parameter CACHE_SIZE    = 1024,
    parameter SETS          = 256,
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 18,
    parameter SET_WIDTH     = 8,
    parameter OFFSET_WIDTH  = 6
) (
    input  logic                        clk, reset,
    input  logic                        write_en,hit,
    input  logic [ADDRESS_WIDTH - 1 : 0]mem_add,
    input  logic [DATA_WIDTH - 1 : 0]   cache_data_in,cache_data_in_from_main_mem,
    output logic [DATA_WIDTH - 1 : 0]   cache_data_out,cache_data_out_to_main_mem,
    output logic                        data_ready,write_to_main_mem,
    output logic [DATA_WIDTH - 1 : 0]   data_out
);

localparam ADD           = ADDRESS_WIDTH;
localparam TAG_IN_ADD    = SET_WIDTH + OFFSET_WIDTH;
localparam SET_IN_ADD    = OFFSET_WIDTH;

//from cpu
wire [TAG_WIDTH - 1 : 0]    tag_match    = mem_add[ADD - 1 : TAG_IN_ADD];        //tag separation
wire [SET_WIDTH - 1 : 0]    set_match    = mem_add[TAG_IN_ADD - 1 : SET_IN_ADD]; //set separation
wire [OFFSET_WIDTH - 1 : 0] offset_match = mem_add[SET_IN_ADD - 1 : 0];          //offset separation

typedef enum logic [2:0] { idle, cache_dirty, cache_not_dirty } state_type;
state_type state_curr, state_next;

logic                        cpu_req, cache_h;
logic                        mem_ready;
logic                        mem_dirty;

always @(posedge clk , posedge reset) begin
    if(reset) begin
        state_curr                 <= idle;
        mem_ready                  <= 1'b0;
        mem_dirty                  <= 1'b0;
        cpu_req                    <= 1'b0;
        cache_h                    <= 1'b0;
        cache_data_out             <= 'b0;
        data_ready                 <= 1'b0;
        write_to_main_mem          <= 1'b0;
        cache_data_out_to_main_mem <= 'b0;
        data_out                   <= 'b0;
    end
    else begin
        state_curr   <= state_next;
    end 

end

always @(*) begin
    state_next                 = state_curr;
    cache_data_out             = 'b0;
    cache_data_out_to_main_mem = 'b0;
    data_ready                 = 1'b0;
    write_to_main_mem          = 1'b0;
    data_out                   = 'b0;     
    case (state_curr)
        idle: begin
            if(cpu_req == 1'b1) begin
                if (hit) begin
                    cache_h    = 1'b1;
                    state_next = idle;
                end elseif(mem_dirty) begin
                    cache_h    = 1'b0;
                    state_next = cache_dirty;
                end
                else begin
                    cache_h = 1'b0;
                    state_next = cache_not_dirty;
                end
            end
        end
        cache_dirty: begin
            //write back to main mem
            //set valid bit to 0
            data_out_to_main_mem = cache_data_out_to_main_mem;
            write_to_main_mem    = 1'b1;
            if(~mem_ready) begin
                state_next = cache_dirty;
            end else begin
                state_next = cache_not_dirty;
            end 
        end
        cache_not_dirty: begin
            //write into cache from main memory 
            data_out   = cache_data_in_from_main_mem;
            data_ready = 1'b1;
            mem_dirty  = 1'b0;
            if(~mem_ready) begin
                state_next = cache_not_dirty;
            end
            else 
            state_next = idle;
        end
    endcase
end
endmodule
