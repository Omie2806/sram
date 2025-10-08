module cache_top #(
    parameter ADDRESS_WIDTH = 32,
    parameter DATA_WIDTH    = 32
) (
    input  logic                         clk, reset, write_en,
    input  logic [DATA_WIDTH - 1 : 0]    data_in,
    input  logic [ADDRESS_WIDTH - 1 : 0] mem_add,
    output logic [DATA_WIDTH - 1 : 0]    data_out,
    output logic                         cache_hit
);


    logic [DATA_WIDTH - 1 : 0] cache_data_out_to_main_mem;
    logic [DATA_WIDTH - 1 : 0] cache_data_in_from_main_mem;
    logic                      data_ready_cache;
    logic                      data_ready_main_mem;
    logic                      write_to_main_mem;


    cache_fsm fsm_inst (
        .clk                    (clk),
        .reset                  (reset),
        .write_en               (write_en),
        .hit                    (cache_hit),
        .mem_add                (mem_add),
        .cache_data_in          (data_in),
        .cache_data_in_from_main_mem (cache_data_in_from_main_mem),
        .cache_data_out_to_main_mem (cache_data_out_to_main_mem),
        .data_ready             (data_ready_cache),
        .write_to_main_mem      (write_to_main_mem),
        .data_out               (data_out)
    );

    cache_mem mem_inst (
        .clk                    (clk),
        .reset                  (reset),
        .write_en               (write_en),
        .write_en_main_mem      (data_ready_main_mem),
        .data_in                (data_in),
        .data_in_main_mem       (cache_data_in_from_main_mem),
        .mem_add                (mem_add),
        .data_ready             (data_ready_cache),
        .data_ready_main_mem    (data_ready_main_mem),
        .data_out_main_mem      (cache_data_out_to_main_mem),
        .data_out               (data_out)
    );

    cache_main_mem main_mem_inst (
        .clk                    (clk),
        .reset                  (reset),
        .write_en               (write_to_main_mem),
        .mem_add                (mem_add),
        .data_in                (cache_data_out_to_main_mem),
        .data_out               (cache_data_in_from_main_mem),
        .data_ready             (data_ready_main_mem)
    );

endmodule
