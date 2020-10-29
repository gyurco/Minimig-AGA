// cpu / cache / sdram testbench
// based on 2013, rok.krajnc@gmail.com

`define SOC_SIM

//// module ////
module cpu_cache_sdram_tb(
  input  wire           clk_114,
  input  wire           reset,
  input  wire    [24:1] cpuAddr,
  input  wire     [1:0] cpuState,
  input  wire           cpuL,
  input  wire           cpuU,
  input  wire           cpuLongWord,
  input  wire [ 16-1:0] cpuWR,
  output wire [ 16-1:0] cpuRD,
  output wire           clkena
);

//// fake cpu ///
reg [3:0] slower;
wire      ramsel = cpuState != 2'b01;
wire      cpu_ncs = ~ramsel | slower[0];

always @(posedge clk_114) begin
	if (clkena)
		slower <= 4'b0111;
	else
		slower <= {1'b0, slower[3:1]};
end

assign    clkena = tg68_ena28 && (cpuState == 2'b01 || tg68_cpuena);
assign    tg68_cpustate = {cpuLongWord, 3'b000, cpu_ncs, cpuState};
assign    tg68_dat_out = cpuWR;
assign    cpuRD = tg68_dat_in;
assign    tg68_cad[24:1] = cpuAddr;
assign    tg68_clds = cpuL;
assign    tg68_cuds = cpuU;

//// internal signals ////

wire           clk_7_en = 0;
// data reg
reg  [16-1:0] dat;

// SDRAM
wire [ 16-1:0] DRAM_DQ;
wire [ 13-1:0] DRAM_ADDR;
wire           DRAM_LDQM = sdram_dqm[0];
wire           DRAM_UDQM = sdram_dqm[1];
wire           DRAM_WE_N;
wire           DRAM_CAS_N;
wire           DRAM_RAS_N;
wire           DRAM_CS_N = sdram_cs[0];
wire           DRAM_BA_0 = sdram_ba[0];
wire           DRAM_BA_1 = sdram_ba[1];
wire           DRAM_CLK = clk_114;
wire           DRAM_CKE = 1'b1;

// SDRAM controller
wire          sdctl_rst;
wire          reset_out;
wire [ 3-1:0] cctrl;
wire          cache_inhibit = 0;

wire [ 4-1:0] sdram_cs;
wire [ 2-1:0] sdram_ba;
wire [ 2-1:0] sdram_dqm;

wire   [24:0] rtgAddr;
wire          rtgce = 0;
wire          rtgfill;
wire   [15:0] rtgRd;

wire   [22:0] audAddr;
wire          audce = 0;
wire          audfill;
wire   [15:0] audRd;

wire [22-1:0] bridge_adr;
wire          bridge_cs;
wire          bridge_we;
wire [32-1:0] bridge_dat_w;
wire [32-1:0] bridge_dat_r;
wire          bridge_ack;
wire          bridge_err;
wire  [4-1:0] bridge_bytesel;
wire [16-1:0] ram_data;
wire [22-1:1] ram_address;
wire          _ram_bhe;
wire          _ram_ble;
wire          _ram_we;
wire          _ram_oe;
wire [16-1:0] ramdata_in;

reg  [32-1:0] tg68_cad=0;
reg  [ 7-1:0] tg68_cpustate=7'b0000001;
reg           tg68_clds=1;
reg           tg68_cuds=1;
wire [16-1:0] tg68_cout;
wire          tg68_ena28;
wire          tg68_ena7RD;
wire          tg68_ena7WR;
wire          tg68_cpuena;
reg           tg68_dtack=0;

reg  [32-1:0] tg68_adr=0;
reg  [16-1:0] tg68_dat_in=0;
reg  [16-1:0] tg68_dat_out=0;
reg           tg68_as=0;
reg           tg68_uds=0;
reg           tg68_lds=0;
reg           tg68_rw=0;


//// toplevel logic ////
assign cctrl = 3'b111;

assign bridge_cs = 1'b0;
assign bridge_adr = 22'd0;
assign bridge_we = 1'b0;
assign bridge_dat_w = 32'd0;

assign ram_address = 21'd0;
assign ram_data = 16'd0;
assign _ram_bhe = 1'b1;
assign _ram_ble = 1'b1;
assign _ram_we = 1'b1;
assign _ram_oe = 1'b1;

//// modules ////

// SDRAM controller
sdram_ctrl sdram_ctrl (
  // sys
  .sysclk       (clk_114          ),
  .clk7_en      (clk_7_en         ),
  .reset_in     (reset            ),
  .cache_rst    (reset            ),
  .reset_out    (reset_out        ),
  .cache_inhibit(cache_inhibit    ),
  .cpu_cache_ctrl(4'b0011         ),
  // sdram
  .sdaddr       (DRAM_ADDR        ),
  .sd_cs        (sdram_cs         ),
  .ba           (sdram_ba         ),
  .sd_we        (DRAM_WE_N        ),
  .sd_ras       (DRAM_RAS_N       ),
  .sd_cas       (DRAM_CAS_N       ),
  .dqm          (sdram_dqm        ),
  .sdata        (DRAM_DQ          ),
  // host
  .hostWR       (bridge_dat_w     ),
  .hostAddr     (bridge_adr       ),
  .hostce       (bridge_cs        ),
  .hostwe       (bridge_we        ),
  .hostbytesel  (bridge_bytesel   ),
  .hostRD       (bridge_dat_r     ),
  .hostena      (bridge_ack       ),
  // chip
  .chipAddr     ({2'b00, ram_address[21:1]}),
  .chipL        (_ram_ble         ),
  .chipU        (_ram_bhe         ),
  .chipRW       (_ram_we          ),
  .chip_dma     (_ram_oe          ),
  .chipWR       (ram_data         ),
  .chipRD       (ramdata_in       ),
  .chip48       (                 ),
  // RTG
  .rtgAddr      (rtgAddr          ),
  .rtgce        (rtgce            ),
  .rtgfill      (rtgfill          ),
  .rtgRd        (rtgRd            ),
  // Audio
  .audAddr      (audAddr          ),
  .audce        (audce            ),
  .audfill      (audfill          ),
  .audRd        (audRd            ),
  // cpu
  .cpuAddr      (tg68_cad[24:1]   ),
  .cpustate     (tg68_cpustate    ),
  .cpuL         (tg68_clds        ),
  .cpuU         (tg68_cuds        ),
  .cpu_dma      (                 ),
  .cpuWR        (tg68_dat_out     ),
  .cpuRD        (tg68_dat_in      ),
  .enaWRreg     (tg68_ena28       ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      ),
  .cpuena       (tg68_cpuena      ),
  .enaRDreg     (                 )
);

// SDRAM
mt48lc16m16a2
sdram (
  .Dq         (DRAM_DQ),
  .Addr       (DRAM_ADDR),
  .Ba         ({DRAM_BA_1, DRAM_BA_0}),
  .Clk        (DRAM_CLK),
  .Cke        (DRAM_CKE),
  .Cs_n       (DRAM_CS_N),
  .Ras_n      (DRAM_RAS_N),
  .Cas_n      (DRAM_CAS_N),
  .We_n       (DRAM_WE_N),
  .Dqm        ({DRAM_UDQM, DRAM_LDQM})
);

endmodule

