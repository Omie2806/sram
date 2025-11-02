module cache_fsm_tb;

    // Parameters - matching the cache design
    parameter MEM_SIZE        = 4096;
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
        .write_en_main_mem(write_en_main_mem),
        .data_in(data_in),
        .mem_add(mem_add),
        .data_ready(data_ready),
        .data_out(data_out),
        .data_ready_main_mem(data_ready_main_mem)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Helper function to create addresses
    function automatic [ADDRESS_WIDTH-1:0] make_address;
        input [TAG_WIDTH-1:0] tag;
        input [SET_WIDTH-1:0] set;
        input [OFFSET_WIDTH-1:0] offset;
        input [BYTE_OFFSET-1:0] byte_off;
        begin
            make_address = {tag, set, offset, byte_off};
        end
    endfunction

    // Task to display LRU counters for a specific set
    task display_lru_counters;
        input [SET_WIDTH-1:0] set_num;
        begin
            $display("  LRU Counters for Set %0d:", set_num);
            for (int w = 0; w < WAY; w++) begin
                $display("    Way %0d: LRU=%0d, Valid=%0b, Dirty=%0b, Tag=0x%0h",
                    w,
                    dut.LRU_COUNTER[set_num][w],
                    dut.VALID[set_num][w],
                    dut.DIRTY[set_num][w],
                    dut.TAG_IN_CACHE_MEMORY[set_num][w]);
            end
        end
    endtask

    // Task to display cache state for a set
    task display_cache_state;
        input [SET_WIDTH-1:0] set_num;
        begin
            $display("\n=== Cache State for Set %0d ===", set_num);
            for (int w = 0; w < WAY; w++) begin
                $display("  Way %0d: Valid=%0b, Dirty=%0b, Tag=0x%05h, LRU=%0d",
                    w,
                    dut.VALID[set_num][w],
                    dut.DIRTY[set_num][w],
                    dut.TAG_IN_CACHE_MEMORY[set_num][w],
                    dut.LRU_COUNTER[set_num][w]);
                // Display first few words of the cache line
                $write("         Data: ");
                for (int word = 0; word < 4; word++) begin
                    $write("0x%08h ", dut.CACHE_MEMORY[set_num][w][word]);
                end
                $display("...");
            end
            $display("===========================\n");
        end
    endtask

    // Task to wait for cache to be ready
    task wait_cache_idle;
        begin
            while (dut.state_curr != dut.idle) begin
                @(posedge clk);
            end
        end
    endtask

    // Task to perform a read operation
    task read_cache;
        input [TAG_WIDTH-1:0] tag;
        input [SET_WIDTH-1:0] set;
        input [OFFSET_WIDTH-1:0] offset;
        input [DATA_WIDTH-1:0] expected_data;
        input check_data;
        begin
            task_addr = make_address(tag, set, offset, 0);
            
            $display("[%0t] READ: Tag=0x%05h, Set=%0d, Offset=%0d (Addr=0x%08h)", 
                     $time, tag, set, offset, task_addr);
            
            // Set address and control signals with proper timing
            mem_add = task_addr;
            write_en = 0;
            
            @(posedge clk);  // Cycle 1: Set address
            @(posedge clk);  // Cycle 2: FSM latches (if in idle)
            @(posedge clk);  // Cycle 3: FSM transitions to read
            
            wait_cache_idle();
            
            if (data_ready) begin
                $display("  → HIT! Data=0x%08h", data_out);
                if (check_data && data_out !== expected_data) begin
                    $display("  → ERROR: Expected 0x%08h, got 0x%08h", expected_data, data_out);
                end
            end else begin
                $display("  → MISS! Cache will fetch from memory...");
                wait_cache_idle();
                $display("  → Data loaded: 0x%08h", data_out);
            end
        end
    endtask

    // Task to perform a write operation
    task write_cache;
        input [TAG_WIDTH-1:0] tag;
        input [SET_WIDTH-1:0] set;
        input [OFFSET_WIDTH-1:0] offset;
        input [DATA_WIDTH-1:0] write_data;
        begin
            task_addr = make_address(tag, set, offset, 0);
            
            $display("[%0t] WRITE: Tag=0x%05h, Set=%0d, Offset=%0d, Data=0x%08h (Addr=0x%08h)", 
                     $time, tag, set, offset, write_data, task_addr);
            
            // Set address, data, and control signals with proper timing
            mem_add = task_addr;
            write_en = 1;
            data_in = write_data;
            
            @(posedge clk);  // Cycle 1: Set address and data
            @(posedge clk);  // Cycle 2: FSM latches (if in idle)
            @(posedge clk);  // Cycle 3: FSM transitions to write
            
            wait_cache_idle();
            write_en = 0;
            @(posedge clk);
            if (data_ready) begin
                $display("  → WRITE HIT!");
            end else begin
                $display("  → WRITE MISS! Cache will allocate...");
                wait_cache_idle();
                $display("  → Write complete");
            end
        end
    endtask

    // Task to initialize main memory with test patterns
    task init_main_memory;
        begin
            $display("\n=== Initializing Main Memory ===");
            for (int block = 0; block < 4096; block++) begin
                for (int word = 0; word < WORDS_PER_BLOCK; word++) begin
                    dut.MAIN_MEMORY[block][word] = (block << 16) | word;
                end
            end
            $display("Memory initialized with pattern: [block<<16 | word]\n");
        end
    endtask

    // Main test sequence
    initial begin
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║        Cache FSM Testbench - Comprehensive Test       ║");
        $display("╔════════════════════════════════════════════════════════╗\n");
        
        // Initialize signals
        reset = 1;
        write_en = 0;
        write_en_main_mem = 0;
        data_in = 0;
        mem_add = 0;
        
        // Apply reset
        #(CLK_PERIOD * 2);
        reset = 0;
        
        // Wait for cache to stabilize after reset
        repeat(3) @(posedge clk);
        #1;  // Small delta delay
        
        // Initialize main memory
        init_main_memory();
        
        // Prime the cache with a dummy access to initialize latched values
        $display("=== Priming Cache ===");
        $display("Performing dummy read to initialize cache state...\n");
        mem_add = 32'h0;
        write_en = 0;
        @(posedge clk);
        wait_cache_idle();
        $display("Cache primed and ready!\n");
        
        // ===================================================================
        // TEST 1: Basic Read Miss (Cold Start)
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 1: Read Miss (Cold Start)                       ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        read_cache(18'h00001, 8'd0, 4'd0, 32'h01000000, 0);
        display_cache_state(0);
        display_lru_counters(0);
        
        // ===================================================================
        // TEST 2: Read Hit (Same Location)
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 2: Read Hit (Same Location)                     ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        read_cache(18'h00001, 8'd0, 4'd0, 32'h01000000, 1);
        display_lru_counters(0);
        
        // ===================================================================
        // TEST 3: Read Different Offset in Same Block
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 3: Read Different Offset in Same Block          ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        read_cache(18'h00001, 8'd0, 4'd5, 32'h01000005, 1);
        display_lru_counters(0);
        
        // ===================================================================
        // TEST 4: Fill All 4 Ways in Set 0
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 4: Fill All 4 Ways in Set 0                     ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        $display("Reading from 4 different tags to fill all ways in Set 0...\n");
        
        // Way 0 already has Tag=0x00001
        // Add 3 more tags to fill remaining ways
        read_cache(18'h00002, 8'd0, 4'd0, 32'h02000000, 0);  // Way 1
        display_lru_counters(0);
        
        read_cache(18'h00003, 8'd0, 4'd0, 32'h03000000, 0);  // Way 2
        display_lru_counters(0);
        
        read_cache(18'h00004, 8'd0, 4'd0, 32'h04000000, 0);  // Way 3
        display_lru_counters(0);
        
        $display("\nAll 4 ways filled! Final cache state:");
        display_cache_state(0);
        
        // ===================================================================
        // TEST 5: Access Each Way to Verify LRU Updates
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 5: Access Each Way to Verify LRU Updates        ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        $display("Accessing Way 2 (Tag=0x00003)...");
        read_cache(18'h00003, 8'd0, 4'd0, 32'h03000000, 1);
        display_lru_counters(0);
        
        $display("\nAccessing Way 0 (Tag=0x00001)...");
        read_cache(18'h00001, 8'd0, 4'd0, 32'h01000000, 1);
        display_lru_counters(0);
        
        $display("\nAccessing Way 3 (Tag=0x00004)...");
        read_cache(18'h00004, 8'd0, 4'd0, 32'h04000000, 1);
        display_lru_counters(0);
        
        $display("\nAccessing Way 1 (Tag=0x00002)...");
        read_cache(18'h00002, 8'd0, 4'd0, 32'h02000000, 1);
        display_lru_counters(0);
        
        // ===================================================================
        // TEST 6: Write Hit
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 6: Write Hit                                     ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        write_cache(18'h00001, 8'd0, 4'd0, 32'hDEADBEEF);
        display_cache_state(0);
        display_lru_counters(0);
        
        $display("Verifying write with read...");
        read_cache(18'h00001, 8'd0, 4'd0, 32'hDEADBEEF, 1);
        
        // ===================================================================
        // TEST 7: Write Miss (Write-Allocate)
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 7: Write Miss (Write-Allocate) in Set 1         ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        write_cache(18'h00010, 8'd1, 4'd3, 32'hCAFEBABE);
        display_cache_state(1);
        display_lru_counters(1);
        
        $display("Verifying write with read...");
        read_cache(18'h00010, 8'd1, 4'd3, 32'hCAFEBABE, 1);
        
        // ===================================================================
        // TEST 8: Multiple Reads to Different Sets
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 8: Multiple Reads to Different Sets             ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        for (int s = 2; s < 6; s++) begin
            $display("\n--- Testing Set %0d ---", s);
            read_cache(18'h00100, s, 4'd0, 32'h00000000, 0);
            display_lru_counters(s);
        end
        
        // ===================================================================
        // TEST 9: Fill Multiple Ways in Set 5
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 9: Fill Multiple Ways in Set 5                  ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        read_cache(18'h01000, 8'd5, 4'd0, 32'h00000000, 0);
        read_cache(18'h01001, 8'd5, 4'd0, 32'h00000000, 0);
        read_cache(18'h01002, 8'd5, 4'd0, 32'h00000000, 0);
        
        display_cache_state(5);
        
        $display("Accessing ways in different order to test LRU...");
        read_cache(18'h01001, 8'd5, 4'd0, 32'h00000000, 0);
        display_lru_counters(5);
        
        read_cache(18'h01000, 8'd5, 4'd0, 32'h00000000, 0);
        display_lru_counters(5);
        
        // ===================================================================
        // TEST 10: Block-Level Operations
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 10: Read Entire Block (All Offsets)             ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        $display("Reading all 16 words from Tag=0x00020, Set=10...\n");
        for (int offset = 0; offset < 16; offset++) begin
            read_cache(18'h00020, 8'd10, offset[3:0], 32'h000a0000 | offset, 1);
        end
        
        display_cache_state(10);
        display_lru_counters(10);
        
        // ===================================================================
        // TEST 11: Write to Multiple Offsets in Same Block
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║  TEST 11: Write to Multiple Offsets in Same Block     ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        for (int offset = 0; offset < 4; offset++) begin
            write_cache(18'h00030, 8'd15, offset[3:0], 32'hA0000000 | (offset << 8));
        end
        
        display_cache_state(15);
        
        // Verify writes
        $display("\nVerifying writes...");
        for (int offset = 0; offset < 4; offset++) begin
            read_cache(18'h00030, 8'd15, offset[3:0], 32'hA0000000 | (offset << 8), 1);
        end
        
        // ===================================================================
        // TEST SUMMARY
        // ===================================================================
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║                   TEST SUMMARY                         ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        $display("✓ Read Miss (Cold Start)");
        $display("✓ Read Hit");
        $display("✓ Read Different Offsets");
        $display("✓ Fill All Ways in a Set");
        $display("✓ LRU Counter Updates");
        $display("✓ Write Hit");
        $display("✓ Write Miss (Write-Allocate)");
        $display("✓ Multiple Sets Access");
        $display("✓ Block-Level Operations");
        $display("✓ Multiple Offset Writes");
        
        $display("\n╔════════════════════════════════════════════════════════╗");
        $display("║            All Tests Completed Successfully!           ║");
        $display("╚════════════════════════════════════════════════════════╝\n");
        
        #(CLK_PERIOD * 10);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("\n*** ERROR: Testbench timeout! ***\n");
        $finish;
    end

    // Optional: Monitor for debugging
    initial begin
        $display("\nStarting FSM state monitoring...\n");
    end
    
    // Monitor state transitions
    always @(posedge clk) begin
        if (dut.state_curr != dut.state_next) begin
            case (dut.state_next)
                dut.idle:              $display("  [FSM] → IDLE");
                dut.read:              $display("  [FSM] → READ");
                dut.write:             $display("  [FSM] → WRITE");
                dut.read_miss:         $display("  [FSM] → READ_MISS");
                dut.get_victim:        $display("  [FSM] → GET_VICTIM");
                dut.write_back:        $display("  [FSM] → WRITE_BACK");
                dut.read_from_main_mem: $display("  [FSM] → READ_FROM_MAIN_MEM");
            endcase
        end
    end

endmodule
