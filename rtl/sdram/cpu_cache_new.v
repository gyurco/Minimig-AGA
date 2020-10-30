// cpu_cache_new.v
// 2015, rok.krajnc@gmail.com
// this is a 2-way set-associative cache
// seperate instruction and data caches
// write-through, look-through
// 8kB cache size, 4kB per way
// whole cache size (I+D) is 16kB
// ! requires Altera Quartus prepared memories because of the byte-selects !

// AMR - adjust for 8-word bursts.

module cpu_cache_new (
  // system
  input  wire           clk,            // clock
  input  wire           rst,            // cache reset
  input  wire           cache_en,       // cache enable
  input  wire [  4-1:0] cpu_cache_ctrl, // CPU cache control
  input  wire           cache_inhibit,  // cache inhibit
  // cpu
  input  wire           cpu_cs,         // cpu activity
  input  wire [ 25-1:0] cpu_adr,        // cpu address
  input  wire [  2-1:0] cpu_bs,         // cpu byte selects
  input  wire           cpu_32bit,      // cpu 32 bit write
  input  wire           cpu_we,         // cpu write
  input  wire           cpu_ir,         // cpu instruction read
  input  wire           cpu_dr,         // cpu data read
  input  wire [ 16-1:0] cpu_dat_w,      // cpu write data
  output wire [ 16-1:0] cpu_dat_r,      // cpu read data
  output                cpu_ack,        // cpu acknowledge
  // sdram
  input  wire [ 16-1:0] sdr_dat_r,      // sdram read data
  output reg            sdr_read_req,   // sdram read request from cache
  input  wire           sdr_read_ack,   // sdram read acknowledge to cache
  output reg  [ 25-1:1] sdr_adr,        // sdram address
  output reg  [ 32-1:0] sdr_dat_w,      // sdram write data
  output reg  [  4-1:0] sdr_dqm_w,      // sdram write byte selects (active low)
  output reg            sdr_write_req,  // sdram write request from cache
  output reg            sdr_writebk_req,// sdram writeback request from cache
  input  wire           sdr_write_ack,  // sdram write acknowledge to cache
  // snoop
  input  wire           snoop_act,      // snoop act (write only - just update existing data in cache)
  input  wire [ 25-1:0] snoop_adr,      // chip address
  input  wire [ 16-1:0] snoop_dat_w     // snoop write data
);


//// internal signals ////

// cache init
reg           cache_init_done;
// state
reg  [ 5-1:0] cpu_sm_state;
reg  [ 4-1:0] sdr_sm_state;
reg           write_ena;
// state signals
reg           fill;
reg           cpu_acked;
reg           cpu_cache_ack;
wire          cpu_32bit_ena;
reg  [11-1:0] cpu_sm_adr;
wire [11-1:0] cpu_sm_adr_next = { cpu_sm_adr[10:3], cpu_sm_adr[2:0] + 2'b01 };
reg           cpu_sm_itag_we;
reg           cpu_sm_dtag_we;
reg           cpu_sm_iram0_we;
reg           cpu_sm_iram1_we;
reg           cpu_sm_dram0_we;
reg           cpu_sm_dram1_we;
reg  [ 4-1:0] cpu_sm_bs;
reg  [32-1:0] cpu_sm_mem_dat_w;
reg  [32-1:0] cpu_sm_itag_dat_w;
reg  [32-1:0] cpu_sm_dtag_dat_w;
reg           cpu_sm_id;
reg           cpu_sm_ilru;
reg           cpu_sm_dlru;
reg  [14-1:0] sdr_sm_tag_adr;
reg  [10-1:0] sdr_sm_adr;
reg           sdr_sm_itag_we;
reg           sdr_sm_dtag_we;
reg           sdr_sm_iram0_we;
reg           sdr_sm_iram1_we;
reg           sdr_sm_dram0_we;
reg           sdr_sm_dram1_we;
reg  [32-1:0] sdr_sm_mem_dat_w;
reg  [32-1:0] sdr_sm_tag_dat_w;
reg           sdr_sm_id;
reg           sdr_sm_ilru;
reg           sdr_sm_dlru;

// cpu cache control
reg  [ 2-1:0] cc_clr_r;
wire          cpu_cache_enable;
wire          cpu_cache_freeze;
wire          cpu_cache_clear;
reg           cc_en;
reg           cc_fr;
reg           cc_clr;
// cpu address
reg  [ 3-1:0] cpu_adr_blk_ptr;
wire [ 3-1:0] cpu_adr_blk_ptr_next = {cpu_adr_blk_ptr[2:1] + 1'd1, 1'b0};
wire [ 3-1:0] cpu_adr_blk_ptr_prev = {cpu_adr_blk_ptr[2:1] - 1'd1, 1'b0};
wire [25-1:0] cpu_adr_prev = {cpu_adr[24:4], cpu_adr[3:1] - 1'd1, cpu_adr[0]};
wire [ 3-1:0] cpu_adr_blk;
wire [ 8-1:0] cpu_adr_idx;
wire [13-1:0] cpu_adr_tag;
// cache line cache
reg   [8-1:0] cpu_cacheline_lo[8];
reg   [8-1:0] cpu_cacheline_hi[8];
reg  [25-1:4] cpu_cacheline_adr;
wire          cpu_cacheline_valid;
reg           cpu_cacheline_dirty;
reg           cpu_cacheline_match;
reg   [2-1:0] cpu_cacheline_cnt;
// idram0
wire [10-1:0] idram0_cpu_adr;
wire [ 4-1:0] idram0_cpu_bs;
wire          idram0_cpu_we;
wire [32-1:0] idram0_cpu_dat_w;
wire [32-1:0] idram0_cpu_dat_r;
wire [10-1:0] idram0_sdr_adr;
wire [ 4-1:0] idram0_sdr_bs;
wire          idram0_sdr_we;
wire [32-1:0] idram0_sdr_dat_w;
wire [32-1:0] idram0_sdr_dat_r;
// idram1
wire [10-1:0] idram1_cpu_adr;
wire [ 4-1:0] idram1_cpu_bs;
wire          idram1_cpu_we;
wire [32-1:0] idram1_cpu_dat_w;
wire [32-1:0] idram1_cpu_dat_r;
wire [10-1:0] idram1_sdr_adr;
wire [ 4-1:0] idram1_sdr_bs;
wire          idram1_sdr_we;
wire [32-1:0] idram1_sdr_dat_w;
wire [32-1:0] idram1_sdr_dat_r;
// ddram0
wire [10-1:0] ddram0_cpu_adr;
wire [ 4-1:0] ddram0_cpu_bs;
wire          ddram0_cpu_we;
wire [32-1:0] ddram0_cpu_dat_w;
wire [32-1:0] ddram0_cpu_dat_r;
wire [10-1:0] ddram0_sdr_adr;
wire [ 4-1:0] ddram0_sdr_bs;
wire          ddram0_sdr_we;
wire [32-1:0] ddram0_sdr_dat_w;
wire [32-1:0] ddram0_sdr_dat_r;
// ddram1
wire [10-1:0] ddram1_cpu_adr;
wire [ 4-1:0] ddram1_cpu_bs;
wire          ddram1_cpu_we;
wire [32-1:0] ddram1_cpu_dat_w;
wire [32-1:0] ddram1_cpu_dat_r;
wire [10-1:0] ddram1_sdr_adr;
wire [ 4-1:0] ddram1_sdr_bs;
wire          ddram1_sdr_we;
wire [32-1:0] ddram1_sdr_dat_w;
wire [32-1:0] ddram1_sdr_dat_r;
// itram
wire [ 8-1:0] itram_cpu_adr;
wire          itram_cpu_we;
wire [32-1:0] itram_cpu_dat_w;
wire [32-1:0] itram_cpu_dat_r;
wire [ 8-1:0] itram_sdr_adr;
wire          itram_sdr_we;
wire [32-1:0] itram_sdr_dat_w;
wire [32-1:0] itram_sdr_dat_r;
wire          itag0_match;
wire          itag1_match;
wire          itag0_hit;
wire          itag1_hit;
wire          itag_lru;
wire          itag0_valid;
wire          itag1_valid;
wire          itag0_dirty;
wire          itag1_dirty;
wire          sdr_itag0_match;
wire          sdr_itag1_match;
wire          sdr_itag_hit;
wire          sdr_itag_lru;
wire          sdr_itag0_valid;
wire          sdr_itag1_valid;
// dtram
wire [ 8-1:0] dtram_cpu_adr;
wire          dtram_cpu_we;
wire [32-1:0] dtram_cpu_dat_w;
wire [32-1:0] dtram_cpu_dat_r;
wire [ 8-1:0] dtram_sdr_adr;
wire          dtram_sdr_we;
wire [32-1:0] dtram_sdr_dat_w;
wire [32-1:0] dtram_sdr_dat_r;
wire          dtag0_match;
wire          dtag1_match;
wire          dtag0_hit;
wire          dtag1_hit;
wire          dtag_lru;
wire          dtag0_valid;
wire          dtag1_valid;
wire          dtag0_dirty;
wire          dtag1_dirty;
wire          sdr_dtag0_match;
wire          sdr_dtag1_match;
wire          sdr_dtag_hit;
wire          sdr_dtag_lru;
wire          sdr_dtag0_valid;
wire          sdr_dtag1_valid;

//// params ////

// cpu-side state machine
localparam [4:0]
  CPU_SM_INIT  = 5'd0,
  CPU_SM_IDLE  = 5'd1,
  CPU_SM_WAIT_LOWORD = 5'd2,
  CPU_SM_WRITE_32BIT = 5'd3,
  CPU_SM_WRITE = 5'd4,
  CPU_SM_WB    = 5'd5,
  CPU_SM_READ  = 5'd6,
  CPU_SM_WRITEBACK  = 5'd7,
  CPU_SM_WRITEBACK2 = 5'd8,
  CPU_SM_WRITEBACK3 = 5'd9,
  CPU_SM_WRITEBACK4 = 5'd10,
  CPU_SM_WRITEBACK5 = 5'd11,
  CPU_SM_WRITEBACK6 = 5'd12,
  CPU_SM_WAIT  = 5'd13,
  CPU_SM_SDWAI = 5'd14,
  CPU_SM_FILL1 = 5'd15,
  CPU_SM_FILL2 = 5'd16,
  CPU_SM_FILLW = 5'd17;

// sdram-side state machine
localparam [3:0]
  SDR_SM_INIT0 = 4'd0,
  SDR_SM_INIT1 = 4'd1,
  SDR_SM_IDLE  = 4'd2,
  SDR_SM_SNOOP = 4'd3,
  SDR_SM_FILL  = 4'd4,
  SDR_SM_FILL1 = 4'd5,
  SDR_SM_FILL2 = 4'd6,
  SDR_SM_FILL3 = 4'd7,
  SDR_SM_WAIT  = 4'd12;


//// cpu side ////

// cpu cache control
always @ (posedge clk) begin
  if (rst)
    cc_clr_r <= #1 2'd0;
  else if (!cpu_cs)
    cc_clr_r <= #1 {cc_clr_r[0], cpu_cache_ctrl[3]};
end

assign cpu_cache_enable = cpu_cache_ctrl[0];
assign cpu_cache_freeze = cpu_cache_ctrl[1];
assign cpu_cache_clear  = cc_clr_r[0] && !cc_clr_r[1];

always @ (posedge clk) begin
  if (rst) begin
    cc_en  <= #1 1'b0;
    cc_fr  <= #1 1'b0;
    cc_clr <= #1 1'b0;
  end else if (!cpu_cs) begin
    cc_en  <= #1 cpu_cache_enable;
    cc_fr  <= #1 cpu_cache_freeze;
    cc_clr <= #1 cpu_cache_clear;
  end
end 

// slice up cpu address
assign cpu_adr_blk = cpu_adr[3:1];    // cache block address (inside cache row), 3 bits for 8x16 rows
assign cpu_adr_idx = cpu_adr[11:4];   // cache row address, 8 bits
assign cpu_adr_tag = cpu_adr[24:12];  // tag, 13 bits

always @(posedge clk) cpu_cacheline_match <= cpu_adr[24:4] == cpu_cacheline_adr && !cpu_cacheline_dirty;
assign cpu_cacheline_valid = cpu_cacheline_match && (cpu_sm_state == CPU_SM_IDLE) && (cpu_ir || cpu_dr) && !cache_inhibit;
assign cpu_32bit_ena = cpu_32bit && cpu_cs && write_ena;
assign cpu_ack = cpu_cache_ack || cpu_cacheline_valid || cpu_32bit_ena;
assign cpu_dat_r = {cpu_cacheline_hi[cpu_adr_blk], cpu_cacheline_lo[cpu_adr_blk]};

// cpu side state machine
always @ (posedge clk) begin
  if (rst) begin
    fill              <= #1 1'b0;
    sdr_read_req      <= #1 1'b0;
    sdr_write_req     <= #1 1'b0;
    sdr_writebk_req   <= #1 1'b0;
    write_ena         <= #1 1'b0;
    cpu_cache_ack     <= #1 1'b0;
    cpu_sm_state      <= #1 CPU_SM_INIT;
    cpu_sm_itag_we    <= #1 1'b0;
    cpu_sm_dtag_we    <= #1 1'b0;
    cpu_sm_iram0_we   <= #1 1'b0;
    cpu_sm_iram1_we   <= #1 1'b0;
    cpu_sm_dram0_we   <= #1 1'b0;
    cpu_sm_dram1_we   <= #1 1'b0;
    cpu_sm_bs         <= #1 4'b1111;
    cpu_adr_blk_ptr   <= #1 3'b000;
    cpu_cacheline_dirty <= #1 1'b1;
  end else begin
    // default values
    fill              <= #1 1'b0;
    sdr_read_req      <= #1 1'b0;
    write_ena         <= #1 1'b0;
    cpu_sm_itag_we    <= #1 1'b0;
    cpu_sm_dtag_we    <= #1 1'b0;
    cpu_sm_iram0_we   <= #1 1'b0;
    cpu_sm_iram1_we   <= #1 1'b0;
    cpu_sm_dram0_we   <= #1 1'b0;
    cpu_sm_dram1_we   <= #1 1'b0;
    cpu_sm_bs         <= #1 4'b1111;

    // state machine
    case (cpu_sm_state)
      CPU_SM_INIT : begin
        // waiting for cache init
        if (cache_init_done) begin
          cpu_sm_state <= #1 CPU_SM_IDLE;
        end else begin
          cpu_sm_state <= #1 CPU_SM_INIT;
        end
      end
      CPU_SM_IDLE : begin
        cpu_adr_blk_ptr <= #1 cpu_adr_blk;
        write_ena <= #1 !sdr_write_req && !sdr_write_ack;
        // waiting for CPU access
        if (cpu_cs) begin
          if (cpu_we) begin
            if (!cpu_cacheline_match) cpu_cacheline_dirty <= #1 1'b1; //invalidate
            if (cpu_bs[0]) cpu_cacheline_lo[cpu_adr_blk_ptr] <= #1 cpu_dat_w[ 7: 0]; //update low byte
            if (cpu_bs[1]) cpu_cacheline_hi[cpu_adr_blk_ptr] <= #1 cpu_dat_w[15: 8]; //update hi byte

            if (write_ena) begin
              sdr_adr <= #1 cpu_adr[24:1];
              sdr_dqm_w <= #1 {2'b11, ~cpu_bs};
              sdr_dat_w <= #1 {cpu_dat_w, cpu_dat_w};
              if (cpu_32bit) begin
                cpu_cache_ack <= #1 1'b1;
                cpu_sm_state <= #1 CPU_SM_WAIT_LOWORD;
              end else begin
                //sdr_write_req <= #1 1'b1;
                cpu_sm_state <= #1 CPU_SM_WRITE;
              end
            end
          end else if (!cpu_cacheline_valid) begin
            cpu_adr_blk_ptr <= #1 cpu_adr_blk_ptr_next;
            cpu_sm_state <= #1 CPU_SM_READ;
            cpu_cacheline_cnt <= #1 2'b00;
          end
        end else begin
          if (cc_clr)
            cpu_sm_state <= #1 CPU_SM_INIT;
          else
            cpu_sm_state <= #1 CPU_SM_IDLE;
        end
      end
      CPU_SM_WAIT_LOWORD : begin
        if (!cpu_cs) cpu_sm_state <= #1 CPU_SM_WRITE_32BIT;
      end
      CPU_SM_WRITE_32BIT : if (cpu_cs) begin
        sdr_dqm_w[3:2] <= #1 ~cpu_bs;
        sdr_dat_w[31:16] <= #1 cpu_dat_w;
        //sdr_write_req <= #1 1'b1;

        if (cpu_bs[0])     cpu_cacheline_lo[cpu_adr_blk]      <= #1 cpu_dat_w[ 7: 0]; //update low byte
        if (cpu_bs[1])     cpu_cacheline_hi[cpu_adr_blk]      <= #1 cpu_dat_w[15: 8]; //update hi byte

        // on hit update cache, on miss no update neccessary; tags don't get updated on writes
        if (!cpu_adr_blk[0]) begin
          // unaligned 32 bit write, hi word
          cpu_sm_bs <= #1 {~sdr_dqm_w[1:0], 2'b00};
          cpu_sm_mem_dat_w[31:16] <= #1 sdr_dat_w[15:0];
          //cpu_sm_state <= #1 CPU_SM_WRITE;
        end else begin
          // aligned 32 bit write, do it in one step
          //cpu_cache_ack <= #1 1'b1;
          cpu_sm_bs <= #1 {cpu_bs, ~sdr_dqm_w[1:0]};
          cpu_sm_mem_dat_w <= #1 {cpu_dat_w, sdr_dat_w[15:0]};
          //cpu_sm_state <= #1 CPU_SM_WB;
        end
        cpu_sm_iram0_we <= #1 itag0_hit /*&& !cc_fr*/;
        cpu_sm_iram1_we <= #1 itag1_hit /*&& !cc_fr*/;
        cpu_sm_dram0_we <= #1 dtag0_hit /*&& !cc_fr*/;
        cpu_sm_dram1_we <= #1 dtag1_hit /*&& !cc_fr*/;
        cpu_sm_state <= #1 CPU_SM_WRITE;
      end
      CPU_SM_WRITE : begin
        // update dirty bit on the cacheline
        cpu_sm_itag_dat_w <= #1 {itram_cpu_dat_r[31:29], 1'b0, itag1_dirty | itag1_hit, itram_cpu_dat_r[26:14], itag0_dirty | itag0_hit, itram_cpu_dat_r[12:0]};
        cpu_sm_dtag_dat_w <= #1 {dtram_cpu_dat_r[31:29], 1'b0, dtag1_dirty | dtag1_hit, dtram_cpu_dat_r[26:14], dtag0_dirty | dtag0_hit, dtram_cpu_dat_r[12:0]};
        cpu_sm_itag_we <= #1 itag0_hit || itag1_hit;
        cpu_sm_dtag_we <= #1 dtag0_hit || dtag1_hit;
        sdr_write_req <= #1 cache_inhibit || !(itag0_hit || itag1_hit || dtag0_hit || dtag1_hit);
        //sdr_write_req <= #1 cache_inhibit || !(dtag0_hit || dtag1_hit);
        if (itag0_hit || itag1_hit || dtag0_hit || dtag1_hit) $display("Lazy write: %x",cpu_adr);

        // on hit update cache, on miss no update neccessary
        cpu_adr_blk_ptr <= #1 cpu_adr_blk;
        cpu_sm_bs <= #1 cpu_adr_blk[0] ? {cpu_bs, 2'b00} : {2'b00, cpu_bs};
        cpu_sm_mem_dat_w <= #1 { cpu_dat_w, cpu_dat_w };
        cpu_sm_iram0_we <= #1 itag0_hit /*&& !cc_fr*/;
        cpu_sm_iram1_we <= #1 itag1_hit /*&& !cc_fr*/;
        cpu_sm_dram0_we <= #1 dtag0_hit /*&& !cc_fr*/;
        cpu_sm_dram1_we <= #1 dtag1_hit /*&& !cc_fr*/;
        cpu_cache_ack <= #1 1'b1;

        cpu_sm_state <= #1 CPU_SM_WB;
      end
      CPU_SM_WB : begin
        if (!cpu_cs) cpu_sm_state <= #1 CPU_SM_IDLE;
      end
      CPU_SM_READ : begin
        $display("READ, cacheline: %d", cpu_adr_idx);
        cpu_cacheline_adr <= #1 cpu_adr[24:4];
        cpu_cacheline_cnt <= #1 cpu_cacheline_cnt + 1'b1;
        if(cpu_cacheline_cnt == 2'b01) begin
          cpu_cacheline_dirty <= #1 1'b0;
          cpu_cache_ack <= #1 1'b1; //early ack
        end
        if(cpu_cacheline_cnt == 2'b11)
          cpu_sm_state <= #1 cpu_cs ? CPU_SM_WAIT : CPU_SM_IDLE;

        cpu_adr_blk_ptr <= cpu_adr_blk_ptr_next;
        // on hit update LRU flag in tag memory
        if (cc_en && itag0_hit) begin
          // data is already in instruction cache way 0
          cpu_sm_itag_we <= #1 (cpu_cacheline_cnt == 2'b00); // update at the first cycle only
          cpu_sm_itag_dat_w <= #1 {1'b0, itram_cpu_dat_r[30:0]};
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 idram0_cpu_dat_r[ 7: 0];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 idram0_cpu_dat_r[15: 8];
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 idram0_cpu_dat_r[23:16];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 idram0_cpu_dat_r[31:24];
        end else if (cc_en && itag1_hit) begin
          // data is already in instruction cache way 1
          cpu_sm_itag_we <= #1 (cpu_cacheline_cnt == 2'b00); // update at the first cycle only
          cpu_sm_itag_dat_w <= #1 {1'b1, itram_cpu_dat_r[30:0]};
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 idram1_cpu_dat_r[ 7: 0];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 idram1_cpu_dat_r[15: 8];
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 idram1_cpu_dat_r[23:16];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 idram1_cpu_dat_r[31:24];
        end else if (cc_en && dtag0_hit) begin
          // data is already in data cache way 0
          cpu_sm_dtag_we <= #1 (cpu_cacheline_cnt == 2'b00); // update at the first cycle only
          cpu_sm_dtag_dat_w <= #1 {1'b0, dtram_cpu_dat_r[30:0]};
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 ddram0_cpu_dat_r[ 7: 0];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 ddram0_cpu_dat_r[15: 8];
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 ddram0_cpu_dat_r[23:16];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 ddram0_cpu_dat_r[31:24];
        end else if (cc_en && dtag1_hit) begin
          // data is already in data cache way 1
          cpu_sm_dtag_we <= #1 (cpu_cacheline_cnt == 2'b00); // update at the first cycle only
          cpu_sm_dtag_dat_w <= #1 {1'b1, dtram_cpu_dat_r[30:0]};
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 ddram1_cpu_dat_r[ 7: 0];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b0}] <= #1 ddram1_cpu_dat_r[15: 8];
          cpu_cacheline_lo[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 ddram1_cpu_dat_r[23:16];
          cpu_cacheline_hi[{cpu_adr_blk_ptr_prev[2:1], 1'b1}] <= #1 ddram1_cpu_dat_r[31:24];
        end else begin
          cpu_adr_blk_ptr <= #1 0;
          // on miss fetch data from SDRAM
          // write back dirty data first
          if (!cache_inhibit && cpu_ir && itag_lru && itag0_valid && itag0_dirty) begin
            cpu_sm_state <= #1 CPU_SM_WRITEBACK;
          end else if (!cache_inhibit && cpu_ir && !itag_lru && itag1_valid && itag1_dirty) begin
            cpu_sm_state <= #1 CPU_SM_WRITEBACK;
          end else if (!cache_inhibit && !cpu_ir && dtag_lru && dtag0_valid && dtag0_dirty) begin
            cpu_sm_state <= #1 CPU_SM_WRITEBACK;
          end else if (!cache_inhibit && !cpu_ir && !dtag_lru && dtag1_valid && dtag1_dirty) begin
            cpu_sm_state <= #1 CPU_SM_WRITEBACK;
          end else begin
            cpu_acked <= #1 1'b0;
            if (!sdr_read_ack) begin
              sdr_read_req <= #1 1'b1;
              cpu_sm_state <= #1 CPU_SM_FILL1;
            end else begin
              // wait if the previous request is still going
              // (when the cache is inhibited, we don't wait until the burst is finished)
              cpu_sm_state <= #1 CPU_SM_SDWAI;
            end
          end
        end
      end
      CPU_SM_WAIT : begin
        cpu_adr_blk_ptr <= #1 cpu_adr_blk;
        if (!cpu_cs) cpu_sm_state <= #1 CPU_SM_IDLE;
      end
      CPU_SM_WRITEBACK : begin
        cpu_sm_state <= #1 CPU_SM_WRITEBACK2;
      end
      CPU_SM_WRITEBACK2 : begin
        if (!sdr_write_req && !sdr_write_ack) begin
          if (cpu_ir && itag_lru && itag0_valid && itag0_dirty) begin
            sdr_adr <= #1 {itram_cpu_dat_r[12: 0], cpu_adr_idx, 3'b000};
            sdr_dat_w <= #1 idram0_cpu_dat_r;
          end else if (cpu_ir && !itag_lru && itag1_valid && itag1_dirty) begin
            sdr_adr <= #1 {itram_cpu_dat_r[26:14], cpu_adr_idx, 3'b000};
            sdr_dat_w <= #1 idram1_cpu_dat_r;
          end else if (!cpu_ir && dtag_lru && dtag0_valid && dtag0_dirty) begin
            sdr_adr <= #1 {dtram_cpu_dat_r[12: 0], cpu_adr_idx, 3'b000};
            sdr_dat_w <= #1 ddram0_cpu_dat_r;
          end else if (!cpu_ir && !dtag_lru && dtag1_valid && dtag1_dirty) begin
            sdr_adr <= #1 {dtram_cpu_dat_r[26:14], cpu_adr_idx, 3'b000};
            sdr_dat_w <= #1 ddram1_cpu_dat_r;
          end
          sdr_dqm_w <= #1 4'b0000;
          sdr_writebk_req <= #1 1'b1;
          cpu_adr_blk_ptr <= #1 3'd2;
          cpu_sm_state <= #1 CPU_SM_WRITEBACK3;
        end
      end
      CPU_SM_WRITEBACK3: begin
        if (sdr_write_ack) begin
          cpu_sm_state <= #1 CPU_SM_WRITEBACK4;
        end
      end
      CPU_SM_WRITEBACK4: begin
        // 3th-4th words
        if (!sdr_write_ack) begin
          if (cpu_ir && itag_lru && itag0_valid && itag0_dirty) begin
            sdr_dat_w <= #1 idram0_cpu_dat_r;
          end else if (cpu_ir && !itag_lru && itag1_valid && itag1_dirty) begin
            sdr_dat_w <= #1 idram1_cpu_dat_r;
          end else if (!cpu_ir && dtag_lru && dtag0_valid && dtag0_dirty) begin
            sdr_dat_w <= #1 ddram0_cpu_dat_r;
          end else if (!cpu_ir && !dtag_lru && dtag1_valid && dtag1_dirty) begin
            sdr_dat_w <= #1 ddram1_cpu_dat_r;
          end
          cpu_adr_blk_ptr <= #1 3'd4;
          cpu_cacheline_cnt <= #1 2'd3;
          cpu_sm_state <= #1 CPU_SM_WRITEBACK5;
        end
      end
      CPU_SM_WRITEBACK5: begin
        // 5-6th words
        if (cpu_cacheline_cnt == 0) begin
          if (cpu_ir && itag_lru && itag0_valid && itag0_dirty) begin
            sdr_adr <= #1 {itram_cpu_dat_r[12: 0], cpu_adr_idx, cpu_adr_blk_ptr[2:1], 1'b0};
            sdr_dat_w <= #1 idram0_cpu_dat_r;
          end else if (cpu_ir && !itag_lru && itag1_valid && itag1_dirty) begin
            sdr_adr <= #1 {itram_cpu_dat_r[26:14], cpu_adr_idx, cpu_adr_blk_ptr[2:1], 1'b0};
            sdr_dat_w <= #1 idram1_cpu_dat_r;
          end else if (!cpu_ir && dtag_lru && dtag0_valid && dtag0_dirty) begin
            sdr_adr <= #1 {dtram_cpu_dat_r[12: 0], cpu_adr_idx, cpu_adr_blk_ptr[2:1], 1'b0};
            sdr_dat_w <= #1 ddram0_cpu_dat_r;
          end else if (!cpu_ir && !dtag_lru && dtag1_valid && dtag1_dirty) begin
            sdr_adr <= #1 {dtram_cpu_dat_r[26:14], cpu_adr_idx, cpu_adr_blk_ptr[2:1], 1'b0};
            sdr_dat_w <= #1 ddram1_cpu_dat_r;
          end
        end else begin
          cpu_cacheline_cnt <= cpu_cacheline_cnt - 1'd1;
        end
        if (sdr_write_ack) begin
          sdr_writebk_req <= #1 1'b0;
          cpu_adr_blk_ptr <= 3'd6;
          cpu_sm_state <= #1 CPU_SM_WRITEBACK6;
        end
      end
      CPU_SM_WRITEBACK6: begin
        // 7-8th words
        if (!sdr_write_ack) begin
          if (cpu_ir && itag_lru && itag0_valid && itag0_dirty) begin
            sdr_dat_w <= #1 idram0_cpu_dat_r;
          end else if (cpu_ir && !itag_lru && itag1_valid && itag1_dirty) begin
            sdr_dat_w <= #1 idram1_cpu_dat_r;
          end else if (!cpu_ir && dtag_lru && dtag0_valid && dtag0_dirty) begin
            sdr_dat_w <= #1 ddram0_cpu_dat_r;
          end else if (!cpu_ir && !dtag_lru && dtag1_valid && dtag1_dirty) begin
            sdr_dat_w <= #1 ddram1_cpu_dat_r;
          end
          cpu_acked <= #1 1'b0;
          $display("WRITEBACK cacheline %d", cpu_adr_idx);
          cpu_sm_state <= #1 CPU_SM_SDWAI;
        end
      end
      CPU_SM_SDWAI : begin
        if (!sdr_read_ack) begin
          sdr_read_req <= #1 1'b1;
          cpu_sm_state <= #1 CPU_SM_FILL1;
        end
      end
      CPU_SM_FILL1 : begin
        fill <= #1 1'b1;
        cpu_sm_adr <= #1 {cpu_adr_idx, cpu_adr_blk[2:0]};
        if (!sdr_read_ack) begin
          sdr_read_req <= #1 1'b1;
        end else begin
          sdr_read_req <= #1 1'b0;
          // read data to cpu
          cpu_cache_ack <= #1 1'b1;
          cpu_cacheline_lo[cpu_adr[3:1]] <= #1 sdr_dat_r[7:0];
          cpu_cacheline_hi[cpu_adr[3:1]] <= #1 sdr_dat_r[15:8];
          if (cache_inhibit) begin
            // don't update cache if caching is inhibited
            cpu_cacheline_dirty <= #1 1'b1; //invalidate
            cpu_sm_state <= #1 CPU_SM_FILLW;
          end else begin      
            cpu_cacheline_adr <= #1 cpu_adr[24:4];
            cpu_cacheline_dirty <= #1 1'b0;

            // update tag ram
            if (itag_lru) begin
              cpu_sm_itag_dat_w <= #1 {1'b0, 1'b1, itram_cpu_dat_r[29], 1'b0, itram_cpu_dat_r[27], itram_cpu_dat_r[26:14], 1'b0, cpu_adr_tag};
            end else begin
              cpu_sm_itag_dat_w <= #1 {1'b1, itram_cpu_dat_r[30], 1'b1, 1'b0, 1'b0, cpu_adr_tag, itram_cpu_dat_r[13], itram_cpu_dat_r[12: 0]};
            end
            if (dtag_lru) begin
              cpu_sm_dtag_dat_w <= #1 {1'b0, 1'b1, dtram_cpu_dat_r[29], 1'b0, dtram_cpu_dat_r[27], dtram_cpu_dat_r[26:14], 1'b0, cpu_adr_tag};
            end else begin
              cpu_sm_dtag_dat_w <= #1 {1'b1, dtram_cpu_dat_r[30], 1'b1, 1'b0, 1'b0, cpu_adr_tag, dtram_cpu_dat_r[13], dtram_cpu_dat_r[12: 0]};

            end
            cpu_sm_itag_we <= #1  cpu_ir;
            cpu_sm_dtag_we <= #1 !cpu_ir;
            // cache line fill 1st word
            cpu_sm_id   <= #1 cpu_ir;
            cpu_sm_ilru <= #1 itag_lru;
            cpu_sm_dlru <= #1 dtag_lru;
            cpu_sm_bs <= #1 cpu_adr_blk[0] ? 4'b1100 : 4'b0011;
            cpu_sm_mem_dat_w <= #1 { sdr_dat_r, sdr_dat_r };
            cpu_sm_iram0_we <= #1  itag_lru &&  cpu_ir;
            cpu_sm_iram1_we <= #1 !itag_lru &&  cpu_ir;
            cpu_sm_dram0_we <= #1  dtag_lru && !cpu_ir;
            cpu_sm_dram1_we <= #1 !dtag_lru && !cpu_ir;
            cpu_sm_state <= #1 CPU_SM_FILL2;
          end
        end
      end
      CPU_SM_FILL2 : begin
        if (sdr_read_ack) begin
          if (!cpu_cs) cpu_acked <= #1 1'b1;
          // cache line fill 2nd...8th word
          cpu_cacheline_lo[cpu_sm_adr_next[2:0]] <= #1 sdr_dat_r[7:0];
          cpu_cacheline_hi[cpu_sm_adr_next[2:0]] <= #1 sdr_dat_r[15:8];
          fill <= #1 1'b1;
          cpu_sm_adr[2:0] <= #1 cpu_sm_adr_next[2:0];
          cpu_sm_bs <= #1 ~cpu_sm_bs;
          cpu_sm_mem_dat_w <= #1 { sdr_dat_r, sdr_dat_r };
          cpu_sm_iram0_we <= #1  cpu_sm_ilru &&  cpu_sm_id;
          cpu_sm_iram1_we <= #1 !cpu_sm_ilru &&  cpu_sm_id;
          cpu_sm_dram0_we <= #1  cpu_sm_dlru && !cpu_sm_id;
          cpu_sm_dram1_we <= #1 !cpu_sm_dlru && !cpu_sm_id;
        end else if (!cpu_cs | cpu_acked) begin
          cpu_sm_state <= #1 CPU_SM_IDLE;
          cpu_adr_blk_ptr <= #1 cpu_adr_blk; // if CS already activated during fill
        end
      end
      CPU_SM_FILLW : begin
        if (!cpu_cs) begin
          cpu_sm_state <= #1 CPU_SM_IDLE;
          cpu_adr_blk_ptr <= #1 cpu_adr_blk; // if CS already activated during fill
        end
      end
      default: ;
    endcase

    // when the SDRAM ack'ed the write, lower the request
    if (sdr_write_ack) sdr_write_req <= #1 1'b0;

    // when CPU lowers its request signal, lower ack too
    if (!cpu_cs) cpu_cache_ack <= #1 1'b0;

  end
end


//// sdram side ////

// sdram side state machine
always @ (posedge clk) begin
  if (rst) begin
    cache_init_done   <= #1 1'b0;
    sdr_sm_state      <= #1 SDR_SM_INIT0;
    sdr_sm_itag_we    <= #1 1'b0;
    sdr_sm_dtag_we    <= #1 1'b0;
    sdr_sm_iram0_we   <= #1 1'b0;
    sdr_sm_iram1_we   <= #1 1'b0;
    sdr_sm_dram0_we   <= #1 1'b0;
    sdr_sm_dram1_we   <= #1 1'b0;
  end else begin
    // default values
    cache_init_done   <= #1 1'b1;
    sdr_sm_itag_we    <= #1 1'b0;
    sdr_sm_dtag_we    <= #1 1'b0;
    sdr_sm_iram0_we   <= #1 1'b0;
    sdr_sm_iram1_we   <= #1 1'b0;
    sdr_sm_dram0_we   <= #1 1'b0;
    sdr_sm_dram1_we   <= #1 1'b0;
    // state machine
    case (sdr_sm_state)
      SDR_SM_INIT0 : begin
        // prepare to clear cache
        cache_init_done <= #1 1'b0;
        sdr_sm_adr <= #1 10'd0;
        sdr_sm_tag_dat_w <= #1 32'd0;
        sdr_sm_itag_we <= #1 1'b1;
        sdr_sm_dtag_we <= #1 1'b1;
        sdr_sm_state <= #1 SDR_SM_INIT1;
      end
      SDR_SM_INIT1 : begin
        // clear cache
        cache_init_done <= #1 1'b0;
        sdr_sm_adr <= #1 sdr_sm_adr + 10'd4;
        sdr_sm_itag_we <= #1 1'b1;
        sdr_sm_dtag_we <= #1 1'b1;
        if (&sdr_sm_adr[9:2]) begin
          sdr_sm_state <= #1 SDR_SM_IDLE;
        end else begin
          sdr_sm_state <= #1 SDR_SM_INIT1;
        end
      end
      SDR_SM_IDLE : begin
        // wait for action
        cache_init_done <= #1 1'b1;
        sdr_sm_adr <= #1 snoop_adr[10:1];
        if (cc_clr) begin
          sdr_sm_state <= #1 SDR_SM_INIT0;
        end
        else if (1'b0/*snoop_act*/) begin
          // chip write happening
          sdr_sm_state <= #1 SDR_SM_SNOOP;
        end/* else if (sdr_read_req) begin
          // cpu read cache request
          sdr_sm_tag_adr <= #1 cpu_adr_tag;
          sdr_sm_adr <= #1 {cpu_adr_idx, cpu_adr_blk};
          sdr_sm_state <= #1 SDR_SM_FILL;
        end*/
      end
      SDR_SM_SNOOP : begin
        // update if a matching address is in cache
        /*
        sdr_sm_mem_dat_w <= #1 snoop_dat_w;
        sdr_sm_iram0_we <= #1 sdr_itag0_match && sdr_itag0_valid;
        sdr_sm_iram1_we <= #1 sdr_itag1_match && sdr_itag1_valid;
        sdr_sm_dram0_we <= #1 sdr_dtag0_match && sdr_dtag0_valid;
        sdr_sm_dram1_we <= #1 sdr_dtag1_match && sdr_dtag1_valid;
        sdr_sm_state <= #1 SDR_SM_IDLE;
        */
      end
/*
      SDR_SM_FILL : begin
        if (sdr_read_ack) begin
          sdr_sm_mem_dat_w <= #1 sdr_dat_r;
          sdr_sm_id   <= #1 cpu_ir;
          sdr_sm_ilru <= #1 sdr_itag_lru;
          sdr_sm_dlru <= #1 sdr_dtag_lru;
          sdr_sm_iram0_we <= #1 sdr_itag_lru && cpu_ir;
          sdr_sm_iram1_we <= #1 !sdr_itag_lru && cpu_ir;
          sdr_sm_dram0_we <= #1 sdr_dtag_lru && !cpu_ir;
          sdr_sm_dram1_we <= #1 !sdr_dtag_lru && !cpu_ir;
          sdr_sm_state <= #1 SDR_SM_FILL1;
        end
      end
      SDR_SM_FILL1 : begin
        // writing 1st word, preparing 2nd word
        sdr_sm_adr[1:0] <= #1 sdr_sm_adr[1:0] + 2'b01;
        sdr_sm_mem_dat_w <= #1 sdr_dat_r;
        sdr_sm_iram0_we <= #1 sdr_sm_ilru && sdr_sm_id;
        sdr_sm_iram1_we <= #1 !sdr_sm_ilru && sdr_sm_id;
        sdr_sm_dram0_we <= #1 sdr_sm_dlru && !sdr_sm_id;
        sdr_sm_dram1_we <= #1 !sdr_sm_dlru && !sdr_sm_id;
        sdr_sm_state <= #1 SDR_SM_FILL2;
      end
      SDR_SM_FILL2 : begin
        // writing 2nd word, preparing 3rd word
        sdr_sm_adr[1:0] <= #1 sdr_sm_adr[1:0] + 2'b01;
        sdr_sm_mem_dat_w <= #1 sdr_dat_r;
        sdr_sm_iram0_we <= #1 sdr_sm_ilru && sdr_sm_id;
        sdr_sm_iram1_we <= #1 !sdr_sm_ilru && sdr_sm_id;
        sdr_sm_dram0_we <= #1 sdr_sm_dlru && !sdr_sm_id;
        sdr_sm_dram1_we <= #1 !sdr_sm_dlru && !sdr_sm_id;
        sdr_sm_state <= #1 SDR_SM_FILL3;
      end
      SDR_SM_FILL3 : begin
        // writing 3rd word, preparing 4th word, updating tags
        sdr_sm_adr[1:0] <= #1 sdr_sm_adr[1:0] + 2'b01;
        sdr_sm_mem_dat_w <= #1 sdr_dat_r;
        sdr_sm_iram0_we <= #1 sdr_sm_ilru && sdr_sm_id;
        sdr_sm_iram1_we <= #1 !sdr_sm_ilru && sdr_sm_id;
        sdr_sm_dram0_we <= #1 sdr_sm_dlru && !sdr_sm_id;
        sdr_sm_dram1_we <= #1 !sdr_sm_dlru && !sdr_sm_id;
        if (sdr_sm_id) begin
          if (sdr_sm_ilru) begin
            sdr_sm_tag_dat_w <= #1 {1'b0, 1'b1, itram_sdr_dat_r[29], 1'b0, itram_sdr_dat_r[27:14], sdr_sm_tag_adr};
          end else begin
            sdr_sm_tag_dat_w <= #1 {1'b1, itram_sdr_dat_r[30], 1'b1, 1'b0, sdr_sm_tag_adr, itram_sdr_dat_r[13: 0]};
          end
        end else begin
          if (sdr_sm_dlru) begin
            sdr_sm_tag_dat_w <= #1 {1'b0, 1'b1, dtram_sdr_dat_r[29], 1'b0, dtram_sdr_dat_r[27:14], sdr_sm_tag_adr};
          end else begin
            sdr_sm_tag_dat_w <= #1 {1'b1, dtram_sdr_dat_r[30], 1'b1, 1'b0, sdr_sm_tag_adr, dtram_sdr_dat_r[13: 0]};
          end
        end
        sdr_sm_itag_we <= #1 sdr_sm_id;
        sdr_sm_dtag_we <= #1 !sdr_sm_id;
        sdr_sm_state <= #1 SDR_SM_WAIT;
      end
      SDR_SM_WAIT : begin // TODO needed?
        sdr_sm_adr <= #1 snoop_adr[10:1];
        sdr_sm_state <= #1 SDR_SM_IDLE;
      end
*/
      default: ;
    endcase
  end
end


//// instruction memories ////

// instruction tag ram
assign itram_cpu_adr    = cpu_adr_idx;
assign itram_cpu_we     = cpu_sm_itag_we;
assign itram_cpu_dat_w  = cpu_sm_itag_dat_w;
assign itag0_match      = (cpu_adr_tag == itram_cpu_dat_r[12:0]);
assign itag1_match      = (cpu_adr_tag == itram_cpu_dat_r[26:14]);
assign itag0_hit        = itag0_match && itag0_valid;
assign itag1_hit        = itag1_match && itag1_valid;
assign itag_lru         = itram_cpu_dat_r[31];
assign itag0_valid      = itram_cpu_dat_r[30];
assign itag1_valid      = itram_cpu_dat_r[29];
assign itag0_dirty      = itram_cpu_dat_r[13];
assign itag1_dirty      = itram_cpu_dat_r[27];
assign itram_sdr_adr    = sdr_sm_adr[9:2];
assign itram_sdr_we     = sdr_sm_itag_we;
assign itram_sdr_dat_w  = sdr_sm_tag_dat_w;
assign sdr_itag0_match  = (snoop_adr[23:11] == itram_sdr_dat_r[12:0]);
assign sdr_itag1_match  = (snoop_adr[23:11] == itram_sdr_dat_r[26:14]);
assign sdr_itag_hit     = sdr_itag0_match || sdr_itag1_match;
assign sdr_itag_lru     = itram_sdr_dat_r[31];
assign sdr_itag0_valid  = itram_sdr_dat_r[30];
assign sdr_itag1_valid  = itram_sdr_dat_r[29];

`ifdef SOC_SIM
dpram_inf_256x32
`else
dpram_256x32
`endif
itram (
  .clock      (clk              ),
  .address_a  (itram_cpu_adr    ),
  .wren_a     (itram_cpu_we     ),
  .data_a     (itram_cpu_dat_w  ),
  .q_a        (itram_cpu_dat_r  ),
  .address_b  (itram_sdr_adr    ),
  .wren_b     (itram_sdr_we     ),
  .data_b     (itram_sdr_dat_w  ),
  .q_b        (itram_sdr_dat_r  )
);

// instruction data ram 0
assign idram0_cpu_adr   = fill ? cpu_sm_adr[10:1] : {cpu_adr_idx, cpu_adr_blk_ptr[2:1]};
assign idram0_cpu_bs    = cpu_sm_bs;
assign idram0_cpu_we    = cpu_sm_iram0_we;
assign idram0_cpu_dat_w = cpu_sm_mem_dat_w;
assign idram0_sdr_adr   = snoop_adr[9:0];
assign idram0_sdr_bs    = 4'b1111;
assign idram0_sdr_we    = sdr_sm_iram0_we;
assign idram0_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
idram0 (
  .clock      (clk              ),
  .address_a  (idram0_cpu_adr   ),
  .byteena_a  (idram0_cpu_bs    ),
  .wren_a     (idram0_cpu_we    ),
  .data_a     (idram0_cpu_dat_w ),
  .q_a        (idram0_cpu_dat_r ),
  .address_b  (idram0_sdr_adr   ),
  .byteena_b  (idram0_sdr_bs    ),
  .wren_b     (idram0_sdr_we    ),
  .data_b     (idram0_sdr_dat_w ),
  .q_b        (idram0_sdr_dat_r )
);

// instruction data ram 1
assign idram1_cpu_adr   = fill ? cpu_sm_adr[10:1] : {cpu_adr_idx, cpu_adr_blk_ptr[2:1]};
assign idram1_cpu_bs    = cpu_sm_bs;
assign idram1_cpu_we    = cpu_sm_iram1_we;
assign idram1_cpu_dat_w = cpu_sm_mem_dat_w;
assign idram1_sdr_adr   = snoop_adr[9:0];
assign idram1_sdr_bs    = 4'b1111;
assign idram1_sdr_we    = sdr_sm_iram1_we;
assign idram1_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
idram1 (
  .clock      (clk              ),
  .address_a  (idram1_cpu_adr   ),
  .byteena_a  (idram1_cpu_bs    ),
  .wren_a     (idram1_cpu_we    ),
  .data_a     (idram1_cpu_dat_w ),
  .q_a        (idram1_cpu_dat_r ),
  .address_b  (idram1_sdr_adr   ),
  .byteena_b  (idram1_sdr_bs    ),
  .wren_b     (idram1_sdr_we    ),
  .data_b     (idram1_sdr_dat_w ),
  .q_b        (idram1_sdr_dat_r )
);


//// data data memories ////

// data tag ram
assign dtram_cpu_adr    = cpu_adr_idx;
assign dtram_cpu_we     = cpu_sm_dtag_we;
assign dtram_cpu_dat_w  = cpu_sm_dtag_dat_w;
assign dtag0_match      = (cpu_adr_tag == dtram_cpu_dat_r[12:0]);
assign dtag1_match      = (cpu_adr_tag == dtram_cpu_dat_r[26:14]);
assign dtag0_hit        = dtag0_match && dtag0_valid;
assign dtag1_hit        = dtag1_match && dtag1_valid;
assign dtag_lru         = dtram_cpu_dat_r[31];
assign dtag0_valid      = dtram_cpu_dat_r[30];
assign dtag1_valid      = dtram_cpu_dat_r[29];
assign dtag0_dirty      = dtram_cpu_dat_r[13];
assign dtag1_dirty      = dtram_cpu_dat_r[27];
assign dtram_sdr_adr    = sdr_sm_adr[9:2];
assign dtram_sdr_we     = sdr_sm_dtag_we;
assign dtram_sdr_dat_w  = sdr_sm_tag_dat_w;
assign sdr_dtag0_match  = (snoop_adr[24:11] == dtram_sdr_dat_r[13:0]);
assign sdr_dtag1_match  = (snoop_adr[24:11] == dtram_sdr_dat_r[27:14]);
assign sdr_dtag_hit     = sdr_dtag0_match || sdr_dtag1_match;
assign sdr_dtag_lru     = dtram_sdr_dat_r[31];
assign sdr_dtag0_valid  = dtram_sdr_dat_r[30];
assign sdr_dtag1_valid  = dtram_sdr_dat_r[29];

`ifdef SOC_SIM
dpram_inf_256x32
`else
dpram_256x32
`endif
dtram (
  .clock      (clk              ),
  .address_a  (dtram_cpu_adr    ),
  .wren_a     (dtram_cpu_we     ),
  .data_a     (dtram_cpu_dat_w  ),
  .q_a        (dtram_cpu_dat_r  ),
  .address_b  (dtram_sdr_adr    ),
  .wren_b     (dtram_sdr_we     ),
  .data_b     (dtram_sdr_dat_w  ),
  .q_b        (dtram_sdr_dat_r  )
);

// data data ram 0
assign ddram0_cpu_adr   = fill ? cpu_sm_adr[10:1] : {cpu_adr_idx, cpu_adr_blk_ptr[2:1]};
assign ddram0_cpu_bs    = cpu_sm_bs;
assign ddram0_cpu_we    = cpu_sm_dram0_we;
assign ddram0_cpu_dat_w = cpu_sm_mem_dat_w;
assign ddram0_sdr_adr   = snoop_adr[9:0];
assign ddram0_sdr_bs    = 4'b1111;
assign ddram0_sdr_we    = sdr_sm_dram0_we;
assign ddram0_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
ddram0 (
  .clock      (clk              ),
  .address_a  (ddram0_cpu_adr   ),
  .byteena_a  (ddram0_cpu_bs    ),
  .wren_a     (ddram0_cpu_we    ),
  .data_a     (ddram0_cpu_dat_w ),
  .q_a        (ddram0_cpu_dat_r ),
  .address_b  (ddram0_sdr_adr   ),
  .byteena_b  (ddram0_sdr_bs    ),
  .wren_b     (ddram0_sdr_we    ),
  .data_b     (ddram0_sdr_dat_w ),
  .q_b        (ddram0_sdr_dat_r )
);

// data data ram 1
assign ddram1_cpu_adr   = fill ? cpu_sm_adr[10:1] : {cpu_adr_idx, cpu_adr_blk_ptr[2:1]};
assign ddram1_cpu_bs    = cpu_sm_bs;
assign ddram1_cpu_we    = cpu_sm_dram1_we;
assign ddram1_cpu_dat_w = cpu_sm_mem_dat_w;
assign ddram1_sdr_adr   = snoop_adr[9:0];
assign ddram1_sdr_bs    = 4'b1111;
assign ddram1_sdr_we    = sdr_sm_dram1_we;
assign ddram1_sdr_dat_w = sdr_sm_mem_dat_w;

`ifdef SOC_SIM
dpram_inf_be_1024x32
`else
dpram_be_1024x32
`endif
ddram1 (
  .clock      (clk              ),
  .address_a  (ddram1_cpu_adr   ),
  .byteena_a  (ddram1_cpu_bs    ),
  .wren_a     (ddram1_cpu_we    ),
  .data_a     (ddram1_cpu_dat_w ),
  .q_a        (ddram1_cpu_dat_r ),
  .address_b  (ddram1_sdr_adr   ),
  .byteena_b  (ddram1_sdr_bs    ),
  .wren_b     (ddram1_sdr_we    ),
  .data_b     (ddram1_sdr_dat_w ),
  .q_b        (ddram1_sdr_dat_r )
);


endmodule

