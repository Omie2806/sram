//displays written by AI otherwise it same as my testbench 
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
    parameter BYTES_PER_WORD  = 4;
    
    parameter CLK_PERIOD = 10;

    // Testbench signals
    logic                              clk;
    logic                              write_en;
    logic                              read_en;
    logic                              reset;
    logic [DATA_WIDTH - 1 : 0]         data_in;
    logic [ADDRESS_WIDTH - 1 : 0]      mem_add;
    logic                              stall;
    logic [DATA_WIDTH - 1 : 0]         data_out;
    logic [3 : 0]                      write_bytes_enable;
    logic [2 : 0]                      load_type;

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
        .WORDS_PER_BLOCK(WORDS_PER_BLOCK),
        .BYTES_PER_WORD(BYTES_PER_WORD)
    ) dut (
        .clk(clk),
        .write_en(write_en),
        .read_en(read_en),
        .reset(reset),
        .data_in(data_in),
        .mem_add(mem_add),
        .stall(stall),
        .data_out(data_out),
        .write_bytes_enable(write_bytes_enable),
        .load_type(load_type)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // -----------------------------------------------------------------------
    // Task: print all valid cache lines
    // -----------------------------------------------------------------------
    task print_cache;
        input [127:0] label;  // up to 16 chars
        integer s, w, o;
        reg [31:0] word;
        begin
            $display("\n========================================");
            $display(" CACHE CONTENTS [%s]", label);
            $display("========================================");
            $display(" SET | WAY | VALID | DIRTY | TAG        | BLOCK WORDS (word0 .. word15)");
            for (s = 0; s < SETS; s++) begin
                for (w = 0; w < WAY; w++) begin
                    if (dut.VALID[s][w]) begin
                        $write(" %3d |  %1d  |   %1b   |   %1b   | 0x%05h  | ",
                            s, w,
                            dut.VALID[s][w],
                            dut.DIRTY[s][w],
                            dut.TAG_IN_CACHE_MEMORY[s][w]);
                        for (o = 0; o < WORDS_PER_BLOCK; o++) begin
                            word = {dut.CACHE_MEMORY[s][w][o][3],
                                    dut.CACHE_MEMORY[s][w][o][2],
                                    dut.CACHE_MEMORY[s][w][o][1],
                                    dut.CACHE_MEMORY[s][w][o][0]};
                            $write("%08h ", word);
                        end
                        $display(" LRU=%0d", dut.LRU_COUNTER[s][w]);
                    end
                end
            end
            $display("  (only valid lines shown)");
            $display("  data_out = 0x%08h", data_out);
            $display("========================================\n");
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: print a range of main memory blocks
    // addr_start..addr_end are BYTE addresses — we convert to block indices
    // -----------------------------------------------------------------------
    task print_main_mem_range;
        input [127:0]          label;
        input [ADDRESS_WIDTH-1:0] byte_addr_start;
        input [ADDRESS_WIDTH-1:0] byte_addr_end;
        integer blk, o;
        integer blk_start, blk_end;
        reg [31:0] word;
        begin
            // block index = byte_addr >> (OFFSET_WIDTH + BYTE_OFFSET)
            // but MAIN_MEMORY is indexed by the upper bits [19:0] of victim_addr
            // which equals {tag, set} = addr[25:6] >> nothing, just use addr[19:0]>>6
            // Simpler: show a few blocks bracketing the address
            blk_start = byte_addr_start >> (OFFSET_WIDTH + BYTE_OFFSET);
            blk_end   = byte_addr_end   >> (OFFSET_WIDTH + BYTE_OFFSET);
            $display("\n--- MAIN MEMORY [%s]  blocks %0d..%0d ---", label, blk_start, blk_end);
            for (blk = blk_start; blk <= blk_end; blk++) begin
                $write("  blk[%0d]: ", blk);
                for (o = 0; o < WORDS_PER_BLOCK; o++) begin
                    word = {dut.MAIN_MEMORY[blk][o][3],
                            dut.MAIN_MEMORY[blk][o][2],
                            dut.MAIN_MEMORY[blk][o][1],
                            dut.MAIN_MEMORY[blk][o][0]};
                    $write("%08h ", word);
                end
                $display("");
            end
            $display("--- end main memory ---\n");
        end
    endtask

    // -----------------------------------------------------------------------
    // Main stimulus — identical timing to original testbench
    // -----------------------------------------------------------------------
    initial begin
        reset = 1;
        repeat(2)@(posedge clk);
        reset = 0;

        for(integer i = 0; i < MEM_SIZE; i++) begin
            for (integer j = 0; j < WORDS_PER_BLOCK; j++) begin
                for(integer k = 0; k < BYTES_PER_WORD; k++) begin
                    dut.MAIN_MEMORY[i][j][k] = 0;
                end 
            end
        end

        // ===================================================================
        // TEST 1 – write full word, read it back
        // ===================================================================
        $display("\n##########################################");
        $display("  TEST 1: full-word write + read back");
        $display("  addr=0x0000_00F0  data=0xFBFC_FDFE  be=1111");
        $display("##########################################");

        write_bytes_enable = 4'b1111;
        mem_add = 32'h0000_00F0;
        data_in = 32'hFBFC_FDFE;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);

        load_type = 3'b010;   // LW
        read_en = 1;
        repeat(3)@(posedge clk);
        read_en = 0;

        // --- print after test 1 ---
        print_cache("after TEST1");
        print_main_mem_range("after TEST1", 32'h0000_00F0, 32'h0000_00F0);

        // ===================================================================
        // TEST 2 – byte-enable write (be=0001), unsigned byte read
        // ===================================================================
        $display("\n##########################################");
        $display("  TEST 2: byte write (be=0001) + unsigned byte read");
        $display("  addr=0x0000_00F3  data[7:0]=0xFF  load_type=100 (LBU)");
        $display("##########################################");

        write_bytes_enable = 4'b0001;
        mem_add = 32'b0000_0000_0000_0000_0000_0000_1111_0011;
        data_in = 32'hFFFF_FFFF;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);

        load_type = 3'b100;   // LBU
        read_en = 1;
        repeat(2)@(posedge clk);
        read_en = 0;

        // --- print after test 2 ---
        print_cache("after TEST2");
        print_main_mem_range("after TEST2",
            32'b0000_0000_0000_0000_0000_0000_1111_0011,
            32'b0000_0000_0000_0000_0000_0000_1111_0011);

        // ===================================================================
        // TEST 3 – signed byte read (same address as test 2)
        // ===================================================================
        $display("\n##########################################");
        $display("  TEST 3: signed byte read (same addr)");
        $display("  load_type=000 (LB)  expect sign-extended 0xFF -> 0xFFFFFFFF");
        $display("##########################################");

        load_type = 3'b000;   // LB
        read_en   = 1;
        repeat(2)@(posedge clk);
        read_en = 0;

        // --- print after test 3 (cache unchanged, just different data_out) ---
        $display("  data_out after LB = 0x%08h  (expect 0xFFFFFFFF)", data_out);
        print_cache("after TEST3");

        // ===================================================================
        // TEST 4 – fill remaining ways, check allocation
        // ===================================================================
        $display("\n##########################################");
        $display("  TEST 4: fill all ways (3 more writes to same set)");
        $display("##########################################");

        // way 2
        write_bytes_enable = 4'b1111;
        mem_add = 32'h0F00_00F0;
        data_in = 32'hABAB_FDFE;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);

        load_type = 3'b010;
        read_en = 1;
        repeat(3)@(posedge clk);
        read_en = 0;

        $display("  [4a] after write 0x0F00_00F0:");
        print_cache("TEST4a");

        // way 3
        write_bytes_enable = 4'b1111;
        mem_add = 32'h0D00_00F0;
        data_in = 32'hFBFC_ABAB;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);

        load_type = 3'b010;
        read_en = 1;
        repeat(3)@(posedge clk);
        read_en = 0;

        $display("  [4b] after write 0x0D00_00F0:");
        print_cache("TEST4b");

        // way 4 (halfword enable)
        write_bytes_enable = 4'b0011;
        mem_add = 32'h0B00_00F0;
        data_in = 32'hFBAB_ABFE;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);

        load_type = 3'b010;
        read_en = 1;
        repeat(3)@(posedge clk);
        read_en = 0;

        $display("  [4c] after write 0x0B00_00F0 (all 4 ways now full):");
        print_cache("TEST4c");

        // ===================================================================
        // TEST 5 – force LRU eviction + writeback, re-read from main memory
        // ===================================================================
        $display("\n##########################################");
        $display("  TEST 5: eviction + writeback + re-read from main memory");
        $display("  new write  addr=0x0900_00F0  data=0xDEAD_BEAD");
        $display("  expect LRU victim written back to main memory");
        $display("  then re-read 0x0D00_00F0 -> expect 0xFBFC_ABAB");
        $display("##########################################");

        write_bytes_enable = 4'b1111;
        mem_add = 32'h0900_00F0;
        data_in = 32'hDEAD_BEAD;
        @(posedge clk);
        write_en = 1;
        @(posedge clk);
        write_en = 0;
        repeat(8)@(posedge clk);

        load_type = 3'b010;
        read_en = 1;
        repeat(3)@(posedge clk);
        read_en = 0;

        $display("  [5a] after eviction write:");
        print_cache("TEST5a - post evict");

        // Now read the evicted address back from main memory
        mem_add = 32'h0D00_00F0;
        load_type = 3'b010;
        read_en = 1;
        repeat(10)@(posedge clk);   // expect FBFC_ABAB

        $display("  [5b] re-read 0x0D00_00F0 (from main mem after eviction):");
        $display("       data_out = 0x%08h  (expect 0xFBFC_ABAB)", data_out);
        print_cache("TEST5b - post re-read");

        // Show relevant main memory blocks to confirm writeback landed
        print_main_mem_range("TEST5 writeback check",
            32'h0D00_00F0, 32'h0D00_00F0);
        print_main_mem_range("TEST5 new block",
            32'h0900_00F0, 32'h0900_00F0);

        $finish;
    end
endmodule
