`timescale 1ns/1ps
module mem_tb;
    localparam DATA_WIDTH    = 32;
    localparam ADDRESS_WIDTH = 32;

    logic clk, reset;
    logic write_en, write_en_main_mem;
    logic [DATA_WIDTH - 1 : 0] data_in_main_mem, data_in;
    logic [ADDRESS_WIDTH - 1 : 0] mem_add;

    wire data_ready, data_ready_main_mem;
    wire [DATA_WIDTH - 1 : 0] data_out_main_mem, data_out;

    cache_mem dut (
        .clk(clk),
        .reset(reset),
        .write_en(write_en),
        .write_en_main_mem(write_en_main_mem),
        .data_in(data_in),
        .data_in_main_mem(data_in_main_mem),
        .mem_add(mem_add),
        .data_ready(data_ready),
        .data_ready_main_mem(data_ready_main_mem),
        .data_out_main_mem(data_out_main_mem),
        .data_out(data_out)
    );

    always #5 clk = ~clk;

    initial begin
        $display("TEST START");
        clk               = 0;
        reset             = 1;
        write_en          = 0;
        write_en_main_mem = 0;
        data_in           = 0;
        data_in_main_mem  = 0;
        mem_add           = 0;

        #10 reset = 0;
        $display("RESET DONE");

        // Write to cache
        #10 write_en = 1;
        mem_add = 32'h0000_0010;
        data_in = 32'hDEADBEEF;

        #10 write_en = 0;
        $display("WROTE 0x%h TO ADDRESS %h", data_in, mem_add);

        // Read back (hit)
        #10 mem_add = 32'h0000_0010;
        #10;
        $display("READ BACK 0x%h, HIT = %b", data_out, data_ready);

        //write back
        #10 write_en = 1;
        mem_add = 32'h0000_0100;
        data_in = 32'hDEADBEEF;

        #10 write_en = 0;

        #10 write_en = 1;
        mem_add = 32'h0001_0100;
        data_in = 32'hCAFEBABE;

        #10 write_en = 0;
        #10; 
        $display("WRITE-BACK DATA TO MAIN MEM: 0x%h (expected 0xDEADBEEF)", data_out_main_mem);
        $display("NEW CACHE DATA: 0x%h at address %h", data_in, mem_add);
        $display("WRITE-BACK READY SIGNAL: %b", data_ready_main_mem);

        #50;
        $display("===== Test Complete =====");
        $stop;
    end
endmodule
