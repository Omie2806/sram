module cache_fsm_tb;

    // Parameters - matching the cache design
    parameter MEM_SIZE        = 1048576;
    parameter CACHE_SIZE      = 1024;
    parameter SETS            = 256;
    parameter ADDRESS_WIDTH   = 32;
    parameter DATA_WIDTH      = 32;
    parameter TAG_WIDTH       = 18;
    parameter SET_WIDTH       = 8;
    parameter OFFSET_WIDTH    = 4;
    parameter WAY             = 4;
    parameter BYTE_OFFSET     = 2;
    parameter WORDS_PER_BLOCK = 16;
    
    parameter CLK_PERIOD = 10;

    // Testbench signals
    logic                              clk;
    logic                              write_en;
    logic                              reset;
    logic                              write_en_main_mem;
    logic [DATA_WIDTH - 1 : 0]         data_in;
    logic [ADDRESS_WIDTH - 1 : 0]      mem_add;
    logic                              data_ready;
    logic [DATA_WIDTH - 1 : 0]         data_out;
    logic                              data_ready_main_mem;

    // Helper variables for tasks (declared here for Icarus Verilog compatibility)
    logic [ADDRESS_WIDTH-1:0] task_addr;
    logic [11:0] victim_block_addr;

    // Instantiate the cache FSM
    cache_fsm #(
        .MEM_SIZE(MEM_SIZE),
        .CACHE_SIZE(CACHE_SIZE),
        .SETS(SETS),
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .SET_WIDTH(SET_WIDTH),
        .OFFSET_WIDTH(OFFSET_WIDTH),
        .WAY(WAY),
        .BYTE_OFFSET(BYTE_OFFSET),
        .WORDS_PER_BLOCK(WORDS_PER_BLOCK)
    ) dut (
        .clk(clk),
        .write_en(write_en),
        .reset(reset),
        .data_in(data_in),
        .mem_add(mem_add),
        .data_ready(data_ready),
        .data_out(data_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        reset = 1;
        repeat(2)@(posedge clk);
        reset = 0;

        for(integer  i = 0; i < MEM_SIZE; i++) begin
            for (integer j = 0; j < WORDS_PER_BLOCK; j++) begin
               dut.MAIN_MEMORY[i][j] = j+1; 
            end
        end
        mem_add = 32'h0000_000F;
        data_in = 32'hFFFF_FFFF;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);
        mem_add = 32'h0000_0000;

        mem_add = 32'h00F0_0010;
        repeat(6)@(posedge clk);

        mem_add = 32'h03F0_0001;
        repeat(6)@(posedge clk);

        mem_add = 32'h0570_0010;
        repeat(6)@(posedge clk);

        mem_add = 32'h07F0_0020;
        repeat(8)@(posedge clk);

        mem_add = 32'h09F0_0030;
        data_in = 32'HFFFF_FFFF;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(5)@(posedge clk);

        mem_add = 32'h0BF0_0010;
        repeat(6)@(posedge clk);
       
        mem_add = 32'h0000_000F;
        repeat(9)@(posedge clk);

        mem_add = 32'h0570_0010;
        repeat(6)@(posedge clk);

        mem_add = 32'h09F0_0030;    
        repeat(6)@(posedge clk);    

        mem_add = 32'h0BF0_0010;
        repeat(6)@(posedge clk);

        mem_add = 32'h0DF0_0030;
        data_in = 32'HFFFF_FFFF;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(5)@(posedge clk);   

        mem_add = 32'h00F0_0010;

        repeat(10)@(posedge clk);   
        mem_add = 32'h0000_000F;       
        repeat(8)@(posedge clk); 

        $finish;
    end
endmodule
