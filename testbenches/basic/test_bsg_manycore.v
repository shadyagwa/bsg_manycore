/**
 *  test_bsg_manycore.v
 *
 */

`include "bsg_manycore_packet.vh"

`ifndef bsg_global_X
`error bsg_global_X must be defined; pass it in through the makefile;
`endif

`ifndef bsg_global_Y
`error bsg_global_Y must be defined; pass it in through the makefile;
`endif

`define MAX_CYCLES 1000000

module test_bsg_manycore;
  import bsg_noc_pkg::*; // {P=0, W, E, N, S}

  parameter int bsg_hetero_type_vec_p [0:`bsg_global_Y-1][0:`bsg_global_X-1] = '{`bsg_hetero_type_vec};
  parameter cycle_time_p = 20; // clock period
  parameter max_cycles_p = `MAX_CYCLES;

  // parameters from makefile, must be defined.
  parameter num_tiles_x_p = `bsg_global_X;
  parameter num_tiles_y_p = `bsg_global_Y;
  parameter tgo_x_p = `bsg_tiles_org_X;
  parameter tgo_y_p = `bsg_tiles_org_Y;
  parameter tg_x_dim_p = `bsg_tiles_X;
  parameter tg_y_dim_p = `bsg_tiles_Y;

  parameter extra_io_rows_p = 1;

  parameter x_cord_width_lp = `BSG_SAFE_CLOG2(num_tiles_x_p);
  parameter y_cord_width_lp = `BSG_SAFE_CLOG2(num_tiles_y_p + extra_io_rows_p);
  parameter io_x_cord_p = 0;
  parameter io_y_cord_p = 0;


  parameter data_width_p = 32;
  parameter addr_width_p = 32-2-1-x_cord_width_lp+1;
  parameter load_id_width_p = 12;

  parameter dmem_size_p = 1024;
  parameter vcache_size_p = 4096;
  parameter icache_entries_p = 1024;
  parameter icache_tag_width_p = 12;
  parameter epa_byte_addr_width_p = 18;
  parameter dram_ch_addr_width_p = 32-2-1-x_cord_width_lp; // virtual bank addr width (in word)
  parameter dram_ch_start_col_p = 0;
  parameter dram_ch_num_p = num_tiles_x_p;

  parameter debug_p = 0;

  parameter axi_id_width_p = 6;
  parameter axi_addr_width_p = 64;
  parameter axi_data_width_p = 256;
  parameter axi_burst_len_p = 1;
  localparam axi_strb_width_lp = (axi_data_width_p>>3);
 
  parameter include_vcache_p = 1; 
  parameter no_dram_ctrl_p = 0; // use this to disable DRAM
  parameter vcache_sets_p = 256;
  parameter vcache_ways_p = 2;
  parameter vcache_block_size_in_words_p = 8;


  // clock and reset generation
  //
  wire clk;
  wire reset;

  bsg_nonsynth_clock_gen #(
    .cycle_time_p(cycle_time_p)
  ) clock_gen (
    .o(clk)
  );

  bsg_nonsynth_reset_gen #(
    .num_clocks_p(1)
    ,.reset_cycles_lo_p(1)
    ,.reset_cycles_hi_p(10)
  ) reset_gen (
    .clk_i(clk)
    ,.async_reset_o(reset)
  );


  // The manycore has a 2-FF pipelined reset in 16nm, therefore we need
  // to add a 2 cycle latency to all other modules.
  logic reset_r, reset_rr;

  always_ff @ (posedge clk) begin
    reset_r <= reset;
    reset_rr <= reset_r;
  end


  // instantiate manycore
  //
  `declare_bsg_manycore_link_sif_s(addr_width_p,data_width_p,
    x_cord_width_lp,y_cord_width_lp,load_id_width_p);

  bsg_manycore_link_sif_s [S:N][num_tiles_x_p-1:0] ver_link_li, ver_link_lo;
  bsg_manycore_link_sif_s [E:W][num_tiles_y_p-1:0] hor_link_li, hor_link_lo;
  bsg_manycore_link_sif_s [num_tiles_x_p-1:0] io_link_li, io_link_lo;

  bsg_manycore #(
    .dmem_size_p(dmem_size_p)
    ,.vcache_size_p(vcache_size_p)
    ,.icache_entries_p(icache_entries_p)
    ,.icache_tag_width_p(icache_tag_width_p)
    ,.data_width_p(data_width_p)
    ,.addr_width_p(addr_width_p)
    ,.load_id_width_p(load_id_width_p)
    ,.epa_byte_addr_width_p(epa_byte_addr_width_p)
    ,.dram_ch_addr_width_p(dram_ch_addr_width_p )
    ,.dram_ch_start_col_p (dram_ch_start_col_p)
    ,.num_tiles_x_p(num_tiles_x_p)
    ,.num_tiles_y_p(num_tiles_y_p)
    ,.extra_io_rows_p(extra_io_rows_p)
    ,.hetero_type_vec_p(bsg_hetero_type_vec_p)
    ,.stub_w_p({num_tiles_y_p{1'b0}})
    ,.stub_e_p({num_tiles_y_p{1'b0}})
    ,.stub_n_p({num_tiles_x_p{1'b0}})
    ,.stub_s_p({num_tiles_x_p{1'b0}})
    ,.debug_p(debug_p)
  ) UUT (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.hor_link_sif_i(hor_link_li)
    ,.hor_link_sif_o(hor_link_lo)

    ,.ver_link_sif_i(ver_link_li)
    ,.ver_link_sif_o(ver_link_lo)

    ,.io_link_sif_i(io_link_li)
    ,.io_link_sif_o(io_link_lo)
  );


  // instantiate the loader and moniter
  // connects to (0,0)
  bsg_nonsynth_manycore_io_complex #(
    .addr_width_p(addr_width_p)
    ,.data_width_p(data_width_p)
    ,.x_cord_width_p(x_cord_width_lp)
    ,.y_cord_width_p(y_cord_width_lp)
    ,.load_id_width_p(load_id_width_p)

    ,.num_tiles_x_p(num_tiles_x_p)
    ,.num_tiles_y_p(num_tiles_y_p)
  ) io(
    .clk_i(clk)
    ,.reset_i(reset_rr)
    ,.io_link_sif_i(io_link_lo[0])
    ,.io_link_sif_o(io_link_li[0])
  );


  // instantiate vcache and memory
  //
  if (include_vcache_p) begin: vcache
    
    initial begin
      $display("## Running simulation with vcache.");
    end

    logic [axi_id_width_p-1:0] awid;
    logic [axi_addr_width_p-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic [3:0] awcache;
    logic [2:0] awprot;
    logic awlock;
    logic awvalid;
    logic awready;

    logic [axi_data_width_p-1:0] wdata;
    logic [axi_strb_width_lp-1:0] wstrb;
    logic wlast;
    logic wvalid;
    logic wready;

    logic [axi_id_width_p-1:0] bid;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;

    logic [axi_id_width_p-1:0] arid;
    logic [axi_addr_width_p-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic [3:0] arcache;
    logic [2:0] arprot;
    logic arlock;
    logic arvalid;
    logic arready;

    logic [axi_id_width_p-1:0] rid;
    logic [axi_data_width_p-1:0] rdata;
    logic [1:0] rresp;
    logic rlast;
    logic rvalid;
    logic rready;

    logic [num_tiles_x_p-1:0][x_cord_width_lp-1:0] cache_x;
    logic [num_tiles_x_p-1:0][y_cord_width_lp-1:0] cache_y;

    for (genvar i = 0; i < num_tiles_x_p; i++) begin
      assign cache_x[i] = x_cord_width_lp'(i);
      assign cache_y[i] = y_cord_width_lp'(num_tiles_y_p+1);
    end

    bsg_cache_wrapper_axi #(
      .num_cache_p(num_tiles_x_p)
      ,.data_width_p(data_width_p)
      ,.addr_width_p(addr_width_p)
      ,.block_size_in_words_p(vcache_block_size_in_words_p)
      ,.sets_p(vcache_sets_p)
      ,.ways_p(vcache_ways_p)

      ,.axi_id_width_p(axi_id_width_p)
      ,.axi_addr_width_p(axi_addr_width_p)
      ,.axi_data_width_p(axi_data_width_p)
      ,.axi_burst_len_p(axi_burst_len_p)

      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
      ,.load_id_width_p(load_id_width_p)
    ) vcache_axi (
      .clk_i(clk)
      ,.reset_i(reset)

      ,.my_x_i(cache_x)
      ,.my_y_i(cache_y)

      ,.link_sif_i(ver_link_lo[S])
      ,.link_sif_o(ver_link_li[S])

      ,.axi_awid_o(awid)
      ,.axi_awaddr_o(awaddr)
      ,.axi_awlen_o(awlen)
      ,.axi_awsize_o(awsize)
      ,.axi_awburst_o(awburst)
      ,.axi_awcache_o(awcache)
      ,.axi_awprot_o(awprot)
      ,.axi_awlock_o(awlock)
      ,.axi_awvalid_o(awvalid)
      ,.axi_awready_i(awready)

      ,.axi_wdata_o(wdata)
      ,.axi_wstrb_o(wstrb)
      ,.axi_wlast_o(wlast)
      ,.axi_wvalid_o(wvalid)
      ,.axi_wready_i(wready)

      ,.axi_bid_i(bid)
      ,.axi_bresp_i(bresp)
      ,.axi_bvalid_i(bvalid)
      ,.axi_bready_o(bready)

      ,.axi_arid_o(arid)
      ,.axi_araddr_o(araddr)
      ,.axi_arlen_o(arlen)
      ,.axi_arsize_o(arsize)
      ,.axi_arburst_o(arburst)
      ,.axi_arcache_o(arcache)
      ,.axi_arprot_o(arprot)
      ,.axi_arlock_o(arlock)
      ,.axi_arvalid_o(arvalid)
      ,.axi_arready_i(arready)

      ,.axi_rid_i(rid)
      ,.axi_rdata_i(rdata)
      ,.axi_rresp_i(rresp)
      ,.axi_rlast_i(rlast)
      ,.axi_rvalid_i(rvalid)
      ,.axi_rready_o(rready)
    );

    bsg_manycore_axi_mem #(
      .axi_id_width_p(axi_id_width_p)
      ,.axi_addr_width_p(axi_addr_width_p)
      ,.axi_data_width_p(axi_data_width_p)
      ,.axi_burst_len_p(axi_burst_len_p)
      ,.mem_els_p(2**26) // 2GB
    ) axi_mem (
      .clk_i(clk)
      ,.reset_i(reset)

      ,.axi_awid_i(awid)
      ,.axi_awaddr_i(awaddr)
      ,.axi_awvalid_i(awvalid)
      ,.axi_awready_o(awready)

      ,.axi_wdata_i(wdata)
      ,.axi_wstrb_i(wstrb)
      ,.axi_wlast_i(wlast)
      ,.axi_wvalid_i(wvalid)
      ,.axi_wready_o(wready)

      ,.axi_bid_o(bid)
      ,.axi_bresp_o(bresp)
      ,.axi_bvalid_o(bvalid)
      ,.axi_bready_i(bready)

      ,.axi_arid_i(arid)
      ,.axi_araddr_i(araddr)
      ,.axi_arvalid_i(arvalid)
      ,.axi_arready_o(arready)

      ,.axi_rid_o(rid)
      ,.axi_rdata_o(rdata)
      ,.axi_rresp_o(rresp)
      ,.axi_rlast_o(rlast)
      ,.axi_rvalid_o(rvalid)
      ,.axi_rready_i(rready)
    );
    
  end
  else begin: ram

    initial begin
      $display("## Running simulation with block RAM.");
    end

    for (genvar i = 0; i < num_tiles_x_p; i++) begin
      bsg_manycore_ram_model #(
        .x_cord_width_p(x_cord_width_lp)
        ,.y_cord_width_p(y_cord_width_lp)
        ,.data_width_p(data_width_p)
        ,.addr_width_p(addr_width_p)
        ,.load_id_width_p(load_id_width_p)
        ,.els_p(2**dram_ch_addr_width_p)
      ) ram (
        .clk_i(clk)
        ,.reset_i(reset)

        ,.link_sif_i(ver_link_lo[i])
        ,.link_sif_o(ver_link_li[i])

        ,.my_x_i(x_cord_width_lp'(i))
        ,.my_y_i(y_cord_width_lp'(num_tiles_y_p+1))
      );
    end

  end
  

  // vanilla core tracer
  //
  if (1) begin
    bind vanilla_core vanilla_core_trace #(
      .x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
      ,.icache_tag_width_p(icache_tag_width_p)
      ,.icache_entries_p(icache_entries_p)
      ,.data_width_p(data_width_p)
      ,.dmem_size_p(dmem_size_p)
    ) vtrace (
      .*
    );

    bind vanilla_core instr_trace #(
      .x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
    ) itrace(
      .*
    );
  end

  
  // tieoffs
  //
  for (genvar i = 0; i < num_tiles_y_p; i++) begin

    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.load_id_width_p(load_id_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_w (
      .clk_i(clk)
      ,.reset_i(reset_rr)
      ,.link_sif_i(hor_link_lo[W][i])
      ,.link_sif_o(hor_link_li[W][i])
    );

    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.load_id_width_p(load_id_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_e (
      .clk_i(clk)
      ,.reset_i(reset_rr)
      ,.link_sif_i(hor_link_lo[E][i])
      ,.link_sif_o(hor_link_li[E][i])
    );
  end

  for (genvar i = 0; i < num_tiles_x_p; i++) begin
    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.load_id_width_p(load_id_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_n (
      .clk_i(clk)
      ,.reset_i(reset_rr)
      ,.link_sif_i(ver_link_lo[N][i])
      ,.link_sif_o(ver_link_li[N][i])
    );
  end

  for (genvar i = 1; i < num_tiles_x_p; i++) begin
    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.load_id_width_p(load_id_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_io (
      .clk_i(clk)
      ,.reset_i(reset_rr)
      ,.link_sif_i(io_link_lo[i])
      ,.link_sif_o(io_link_li[i])
    );
  end


endmodule


