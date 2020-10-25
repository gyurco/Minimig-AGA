//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//                                                                          //
// Copyright (c) 2009/2011 Tobias Gubener                                   //
// Subdesign fAMpIGA by TobiFlex                                            //
//                                                                          //
// This source file is free software: you can redistribute it and/or modify //
// it under the terms of the GNU General Public License as published        //
// by the Free Software Foundation, either version 3 of the License, or     //
// (at your option) any later version.                                      //
//                                                                          //
// This source file is distributed in the hope that it will be useful,      //
// but WITHOUT ANY WARRANTY; without even the implied warranty of           //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            //
// GNU General Public License for more details.                             //
//                                                                          //
// You should have received a copy of the GNU General Public License        //
// along with this program.  If not, see <http://www.gnu.org/licenses/>.    //
//                                                                          //
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////


module sdram_ctrl(
  // system
  input  wire           sysclk,
  input  wire           clk7_en,
  input  wire           reset_in,
  input  wire           cache_rst,
  input  wire           cache_inhibit,
  input  wire [  4-1:0] cpu_cache_ctrl,
  output wire           reset_out,
  // sdram
  output reg  [ 13-1:0] sdaddr,
  output wire [  4-1:0] sd_cs,
  output reg  [  2-1:0] ba,
  output wire           sd_we,
  output wire           sd_ras,
  output wire           sd_cas,
  output reg  [  2-1:0] dqm,
  inout  reg  [ 16-1:0] sdata,
  // host
  input  wire [ 32-1:0] hostWR,
  input  wire [ 24-1:2] hostAddr,
  input  wire           hostce,
  input  wire           hostwe,
  input  wire [ 4-1:0 ] hostbytesel,
  output wire [ 32-1:0] hostRD,
  output reg            hostena,
  // chip
  input  wire    [23:1] chipAddr,
  input  wire           chipL,
  input  wire           chipU,
  input  wire           chipRW,
  input  wire           chip_dma,
  input  wire [ 16-1:0] chipWR,
  output reg  [ 16-1:0] chipRD,
  output wire [ 48-1:0] chip48,
  // RTG
  input wire     [24:0] rtgAddr,
  input wire            rtgce,
  output wire           rtgfill,
  output wire    [15:0] rtgRd,
  // Audio
  input wire     [22:0] audAddr,
  input wire            audce,
  output wire           audfill,
  output wire    [15:0] audRd,
  // cpu
  input  wire    [24:1] cpuAddr,
  input  wire [  7-1:0] cpustate,
  input  wire           cpuL,
  input  wire           cpuU,
  input  wire           cpu_dma,
  input  wire [ 16-1:0] cpuWR,
  output wire [ 16-1:0] cpuRD,
  output reg            enaWRreg,
  output reg            ena7RDreg,
  output reg            ena7WRreg,
  output wire           cpuena,
  output reg            enaRDreg
);


//// parameters ////
localparam [2:0]
  REFRESH = 0,
  CHIP = 1,
  CPU_READCACHE = 2,
  CPU_WRITECACHE = 3,
  HOST = 4,
  RTG = 5,
  AUDIO = 6,
  IDLE = 7;

localparam [3:0]
  ph0 = 0,
  ph1 = 1,
  ph2 = 2,
  ph3 = 3,
  ph4 = 4,
  ph5 = 5,
  ph6 = 6,
  ph7 = 7,
  ph8 = 8,
  ph9 = 9,
  ph10 = 10,
  ph11 = 11,
  ph12 = 12,
  ph13 = 13,
  ph14 = 14,
  ph15 = 15;

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

//// local signals ////
reg  [ 4-1:0] initstate;
reg  [ 2-1:0] slot1_dqm;
reg  [ 2-1:0] slot1_dqm2;
reg  [ 2-1:0] slot2_dqm;
reg  [ 2-1:0] slot2_dqm2;
reg           init_done;
wire [16-1:0] datain;
reg  [25-1:0] slot1_addr;
reg  [25-1:0] slot2_addr;
reg  [16-1:0] sdata_reg;
reg  [25-1:2] zmAddr;
reg           zce;
reg           zena;
reg  [32-1:0] hostRDd;
wire [64-1:0] ccache;
wire [25-1:0] ccache_addr;
wire          ccache_fill;
wire          ccachehit;
wire [ 4-1:0] cvalid;
wire          cequal;
wire [ 2-1:0] cpuStated;
wire [16-1:0] cpuRDd;
wire          cpuLongword;
wire          cpuCSn;
wire [64-1:0] dcache;
wire [25-1:0] dcache_addr;
wire          dcache_fill;
wire          dcachehit;
wire [ 4-1:0] dvalid;
wire          dequal;
reg  [ 8-1:0] hostslot_cnt;
reg  [ 8-1:0] reset_cnt;
reg           reset;
reg           reset_sdstate;
reg           clk7_enD;
reg  [ 9-1:0] refreshcnt;
reg           refresh_pending;
reg  [ 4-1:0] sdram_state;
wire [ 2-1:0] pass;
// writebuffer
reg           slot1_write;
reg           slot2_write;
reg  [ 3-1:0] slot1_type = IDLE;
reg  [ 3-1:0] slot2_type = IDLE;
reg  [ 2-1:0] slot1_bank;
reg  [ 2-1:0] slot2_bank;
reg           cache_32bitwrite;
wire          cache_req;
wire          readcache_fill;
reg           cache_fill_1;
reg           cache_fill_2;
reg  [16-1:0] chip48_1;
reg  [16-1:0] chip48_2;
reg  [16-1:0] chip48_3;
wire          longword_en;
reg           longword_wait;
wire          writebuffer_req;
wire [25-1:1] writebufferAddr;
wire [16-1:0] writebufferWR;
reg  [16-1:0] writebufferWR_reg;
wire [ 2-1:0] writebuffer_dqm;
wire [16-1:0] writebufferWR2;
reg  [16-1:0] writebufferWR2_reg;
wire [ 2-1:0] writebuffer_dqm2;
reg           writebuffer_hold;

reg           cache_writeback_req;
reg           cache_writeback_data_req;
reg  [16-1:0] cache_writeback_data;

reg  [25-1:1] cpuAddr_r; // registered CPU address - cpuAddr must be stable one cycle before cpuCSn

reg     [3:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_cs  = {3'b111, sd_cmd[3]};
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

////////////////////////////////////////
// misc signals
////////////////////////////////////////

always @(posedge sysclk) cpuAddr_r <= cpuAddr;

assign cpuLongword = cpustate[6];
assign cpuCSn      = cpustate[2];

////////////////////////////////////////
// reset
////////////////////////////////////////

always @(posedge sysclk) begin
	if(!reset_in) begin
		reset_cnt       <= #1 8'b00000000;
		reset           <= #1 1'b0;
		reset_sdstate   <= #1 1'b0;
	end else begin
		if(reset_cnt == 8'b00101010) begin
			reset_sdstate <= #1 1'b1;
		end
		if(reset_cnt == 8'b10101010) begin
			if(sdram_state == ph15) begin
				reset       <= #1 1'b1;
			end
		end else begin
			reset_cnt     <= #1 reset_cnt + 8'd1;
			reset         <= #1 1'b0;
		end
	end
end

assign reset_out = init_done;


// RTG access

assign rtgRd=sdata_reg;
assign rtgfill=slot2_type==RTG ? cache_fill_2 : 1'b0;
assign audRd=sdata_reg;
assign audfill=slot1_type==AUDIO ? cache_fill_1 : 1'b0;

////////////////////////////////////////
// host access
////////////////////////////////////////

// map host processor's address space to 0x580000
always @ (*) begin
	zmAddr = {2'b00, ~hostAddr[22], hostAddr[21], ~hostAddr[20], ~hostAddr[19], hostAddr[18:2]};
end


// Host cache
// Simplistic direct mapped Cache - 256 x 32bit words, so small enough to fit a single M9K
// - though Quartus chooses to use 2 - not sure why yet.
// 8 word bursts, 16-bit SDRAM interface, so cachelines of 4 32-bit words
// We use a dual-port RAM split between data and tag. 
// (Wasteful, but only requires one memory block.  Since Quartus uses 2 anyway, could use a second?)

// host Cache signals

// 8 bits should result in using just 1 M9K - but doesn't,
// so we might as well make full use of 2 M9Ks with 9 bits.
parameter zcachebits=9;

reg zreq;
reg zbusy;
wire zcachevalid;

wire [zcachebits-1:0] zdata_a;
wire [31:0] zdata_q;
reg[31:0] zdata_w;
reg zdata_wren;

wire [zcachebits-1:0] ztag_a;
wire [31:0] ztag_q;
reg [31:0] ztag_w;
reg ztag_wren;

// Host data always comes from the cache - we don't attempt to bypass during cache filling.
assign hostRD = zdata_q;

// States for state machine
localparam zINIT=0, zWAIT=1, zREAD=2, zPAUSE=3;
localparam zWRITE1=4, zWRITE2=5, zWAITFILL=6;
localparam zFLUSH1=7, zFLUSH2=8;
reg [17:0] zstate;
reg zinitcache;


// In the data blockram the lower two bits of the address determine
// which word of the burst we're reading.  When reading from the cache, this comes
// from the CPU address; when writing to the cache it's determined by the state
// machine.

reg zreadword_burst; // Set to 1 when the lsb of the cache address should
                     // track the SDRAM controller.
reg [1:0] zreadword;

wire [zcachebits-1:0] zcacheline;
assign zcacheline = {1'b0,zmAddr[zcachebits:4],(zreadword_burst ? zreadword : zmAddr[3:2])};

//   zmAddr bits 3:2 specify which words of a burst we're interested in.
//   Bits 10:4 specify the seven bit address of the cachelines;
assign zdata_a = zcacheline;
assign zcachevalid = (ztag_hit && zdata_valid) && !hostwe && !zbusy;


// Dual port RAM.
dpram_inf_generic #(.depth(zcachebits),.width(32)) hostcache(
	.clock(sysclk),
	.address_a(zdata_a),
	.address_b(ztag_a),
	.data_a(zdata_w),
	.data_b(ztag_w),
	.q_a(zdata_q),
	.q_b(ztag_q),
	.wren_a(zdata_wren),
	.wren_b(ztag_wren)
);

wire zdata_valid;

assign zdata_valid = ztag_q[31];


reg [zcachebits-2:0] zinitctr;
assign ztag_a = zinitcache ? {1'b1,zinitctr} :
			{3'b100,zmAddr[zcachebits:4]};

wire ztag_hit;
assign ztag_hit = ztag_q[20:0]==zmAddr[24:4];

always @(posedge sysclk)
begin
	hostena <= hostce & zce & (zena | zcachevalid);

	// Defaults
	zinitcache<=1'b0;

	zbusy <=1'b1;

	case(zstate)

		// We use an init state here to loop through the data, clearing
		// the valid flag - for which we'll use bit 17 of the data entry.

		zINIT:
		begin
			zinitcache<=1'b1;	// need to mark the entire cache as invalid before starting.
			zinitctr<='h00000001;
			ztag_w = 32'h00000000;
			ztag_wren<=1'b1;
			zstate<=zFLUSH2;
		end

		zFLUSH2:
		begin
			zinitcache<=1'b1;
			zinitctr<=zinitctr+1'd1;
			ztag_wren<=1'b1;
			if(zinitctr==0)
			begin
				zstate<=zWAIT;
			end
		end

		zWAIT:
		begin
			zbusy <= 1'b0;
			ztag_w = {4'b1111,7'b0000000,zmAddr[24:4]};
			if(zce)
			begin
				if(hostwe)	// Write cycle - invalidate cacheline (FIXME - only when hit)
				begin
					ztag_w = {4'b0000,7'b0000000,zmAddr[24:4]};
					zreq<=1'b1;
					if(sdram_state==ph0)
						zstate<=zPAUSE;
				end
				else
				begin	// Read cycle
					zstate<=zREAD;
				end
			end
		end

		zREAD:
			begin
				// Check tags for a match...
				if(ztag_hit && zdata_valid)
				begin
					zbusy <= 1'b0;
					zstate<=zPAUSE;
				end
				else if (sdram_state==ph0)	// No matches?  Sync with SDRAM state machine.
				begin
					zreq<=1'b1;
					zstate<=zPAUSE;
				end
			end

		zPAUSE:
		begin
			zbusy <= 1'b0;
			if(slot1_type==HOST && sdram_state==ph2)
			begin
				zreq<=1'b0;
			end

			if(hostce==1'b0) begin
				zstate<=zWAIT;
			end
		end

		default:
			zstate<=zWAIT;
	endcase

	if(!reset) begin
		zstate<=zINIT;
		zena <= #1 1'b0;
		zreadword_burst<=1'b0;
	end else begin

	zce <= #1 hostce;

	if(hostce==1'b0) begin
		zena<=#1 1'b0;
	end

	zdata_wren<=1'b0;
	ztag_wren<=1'b0;

	case(sdram_state)
		ph9 : begin
			if(slot1_type==HOST) begin
				zreadword_burst<=!slot1_write;
				zreadword<=zmAddr[3:2];
				zdata_w[31:16]<=sdata_reg;
			end
		end

		ph10 : begin
			if(slot1_type==HOST) begin
				zdata_w[15:0]<=sdata_reg;
				zdata_wren<=!slot1_write;
				if(slot1_write) begin
					zena <= 1'b1; // Allow write cycles to complete.
					ztag_wren<=1'b1;
				end
			end
		end
		ph11 : begin
			if(slot1_type==HOST) begin
				zreadword<=zreadword+1'd1;
				zdata_w[31:16]<=sdata_reg;
			end
		end

		ph12 : begin
			if(slot1_type==HOST) begin
				zdata_w[15:0]<=sdata_reg;
				zdata_wren<=!slot1_write;
			end
		end

		ph13 : begin
			if(slot1_type==HOST) begin
				zreadword<=zreadword+1'd1;
				zdata_w[31:16]<=sdata_reg;
			end
		end

		ph14 : begin
			if(slot1_type==HOST) begin
				zdata_w[15:0]<=sdata_reg;
				zdata_wren<=!slot1_write;
			end
		end

		ph15 : begin
			if(slot1_type==HOST) begin
				zreadword<=zreadword+1'd1;
				zdata_w[31:16]<=sdata_reg;
			end
		end

		ph0 : begin
			if(slot1_type==HOST) begin
				zdata_w[15:0]<=sdata_reg;
				zdata_wren<=!slot1_write;
			end
		end

		ph1 : begin
			zreadword_burst<=1'b0;
			if(slot1_type==HOST) begin
				ztag_wren<=!slot1_write;	// Only for reads
				zreadword<=zmAddr[3:2];
			end
		end

		default : begin
		end
    endcase
  end
end



////////////////////////////////////////
// cpu cache
////////////////////////////////////////

wire snoop_act;
assign snoop_act = ((sdram_state==ph2)&&(!chipRW));

//// cpu cache ////
cpu_cache_new cpu_cache (
	.clk              (sysclk),                       // clock
	.rst              (!reset || !cache_rst),         // cache reset
	.cache_en         (1'b1),                         // cache enable
	.cpu_cache_ctrl   (cpu_cache_ctrl),               // CPU cache control
	.cache_inhibit    (cache_inhibit),                // cache inhibit
	.cpu_cs           (!cpuCSn),                      // cpu activity
	.cpu_adr          ({cpuAddr, 1'b0}),              // cpu address
	.cpu_bs           ({!cpuU, !cpuL}),               // cpu byte selects
	.cpu_32bit        (longword_en),                  // cpu 32 bit write
	.cpu_we           (&cpustate[1:0]),               // cpu write
	.cpu_ir           (!(|cpustate[1:0])),            // cpu instruction read
	.cpu_dr           (cpustate[1] && !cpustate[0]),  // cpu data read
	.cpu_dat_w        (cpuWR),                        // cpu write data
	.cpu_dat_r        (cpuRD),                        // cpu read data
	.cpu_ack          (ccachehit),                    // cpu acknowledge
	.sdr_dat_r        (sdata_reg),                    // sdram read data
	.sdr_read_req     (cache_req),                    // sdram read request from cache
	.sdr_read_ack     (readcache_fill),               // sdram read acknowledge to cache
	.sdr_adr          (writebufferAddr),
	.sdr_dat_w        ({writebufferWR2, writebufferWR}),
	.sdr_dqm_w        ({writebuffer_dqm2, writebuffer_dqm}),
	.sdr_write_req    (writebuffer_req),
	.sdr_write_ack    (writebuffer_hold),
	.snoop_act        (snoop_act),                    // snoop act (write only - just update existing data in cache)
	.snoop_adr        ({1'b0, chipAddr, 1'b0}),       // snoop address
	.snoop_dat_w      (chipWR)                        // snoop write data
);

assign longword_en = cpuLongword && cpuAddr_r[3:1]!=3'b111 && cpustate[1:0]==2'b11;
assign cpuena = ccachehit;
assign readcache_fill = (cache_fill_1 && slot1_type == CPU_READCACHE) || (cache_fill_2 && slot2_type == CPU_READCACHE);

//// chip line read ////
always @ (posedge sysclk) begin
	if(slot1_type == CHIP) begin
		case(sdram_state)
			ph9  : chipRD   <= #1 sdata_reg;
			ph10 : chip48_1 <= #1 sdata_reg;
			ph11 : chip48_2 <= #1 sdata_reg;
			 ph12 : chip48_3 <= #1 sdata_reg;
		endcase
	end
end

assign chip48 = {chip48_1, chip48_2, chip48_3};



////////////////////////////////////////
// SDRAM control
////////////////////////////////////////

//// clock mangling ////
always @ (posedge sysclk) begin
  clk7_enD <= clk7_en;
end

//// read data reg ////
always @ (posedge sysclk) begin
	sdata_reg <= #1 sdata;
end

//// write / read control ////
always @ (posedge sysclk) begin
	if(!reset_sdstate) begin
		enaRDreg      <= #1 1'b0;
		enaWRreg      <= #1 1'b0;
		ena7RDreg     <= #1 1'b0;
		ena7WRreg     <= #1 1'b0;
	end else begin
		enaRDreg      <= #1 1'b0;
		enaWRreg      <= #1 1'b0;
		ena7RDreg     <= #1 1'b0;
		ena7WRreg     <= #1 1'b0;
		case(sdram_state) // LATENCY=3
			ph2 : begin
				enaWRreg  <= #1 1'b1;
			end
			ph6 : begin
				enaWRreg  <= #1 1'b1;
				ena7RDreg <= #1 1'b1;
			end
			ph10 : begin
				enaWRreg  <= #1 1'b1;
			end
			ph14 : begin
				enaWRreg  <= #1 1'b1;
				ena7WRreg <= #1 1'b1;
			end
			default : begin
			end
		endcase
	end
end


//// init counter ////
always @ (posedge sysclk) begin
	if(!reset) begin
		initstate <= #1 {4{1'b0}};
		init_done <= #1 1'b0;
	end else begin
		case(sdram_state) // LATENCY=3
		ph15 : begin
			if(initstate != 4'b 1111) begin
				initstate <= #1 initstate + 4'd1;
			end else begin
				init_done <= #1 1'b1;
			end
		end
		default : begin
		end
		endcase
	end
end


//// sdram state ////
always @ (posedge sysclk) begin
	if(clk7_enD & ~clk7_en) begin
		sdram_state   <= #1 ph1;
	end else begin
	case(sdram_state) // LATENCY=3
		ph0     : sdram_state <= #1 ph1;
		ph1     : sdram_state <= #1 ph2;
		ph2     : sdram_state <= #1 ph3;
		ph3     : sdram_state <= #1 ph4;
		ph4     : sdram_state <= #1 ph5;
		ph5     : sdram_state <= #1 ph6;
		ph6     : sdram_state <= #1 ph7;
		ph7     : sdram_state <= #1 ph8;
		ph8     : sdram_state <= #1 ph9;
		ph9     : sdram_state <= #1 ph10;
		ph10    : sdram_state <= #1 ph11;
		ph11    : sdram_state <= #1 ph12;
		ph12    : sdram_state <= #1 ph13;
		ph13    : sdram_state <= #1 ph14;
		ph14    : sdram_state <= #1 ph15;
		default : sdram_state <= #1 ph0;
	endcase
	end
end


reg zatn;
reg cpu_reservertg;
reg cpu_slot1ok;
reg cpu_slot2ok;
reg wb_reservertg;
reg wb_slot1ok;
reg wb_slot2ok;
reg rtg_slot2ok;
reg aud_slot1req;

always @(posedge sysclk) begin

	cpu_reservertg <= rtgce && cpuAddr_r[24:23]==rtgAddr[24:23] ? 1'b1 : 1'b0;
	cpu_slot1ok <= !zatn && (slot2_type == IDLE || slot2_bank != cpuAddr_r[24:23]) ? 1'b1 : 1'b0;
	cpu_slot2ok <= !refresh_pending && (|cpuAddr_r[24:23]   // Reserve bank 0 for slot 1
	               && (slot1_type == IDLE || slot1_bank != cpuAddr_r[24:23])) ? 1'b1 : 1'b0;

	wb_reservertg <= rtgce && writebufferAddr[24:23]==rtgAddr[24:23] ? 1'b1 : 1'b0;
	wb_slot1ok <= !zatn && (slot2_type == IDLE || slot2_bank != writebufferAddr[24:23]) ? 1'b1 : 1'b0;
	wb_slot2ok <= !refresh_pending && (|writebufferAddr[24:23] // Reserve bank 0 for slot 1
	           && (slot1_type == IDLE || slot1_bank != writebufferAddr[24:23])) ? 1'b1 : 1'b0;

	rtg_slot2ok <= !refresh_pending && (slot1_type == IDLE || slot1_bank != rtgAddr[24:23]) ? 1'b1 : 1'b0;

	zatn <= !(|hostslot_cnt) && zreq && !hostena;
	aud_slot1req <= slot1_type!=AUDIO && audce & !zatn;
end

//
//reg zatn;
//reg cpureq1;
//
//always @(posedge sysclk) begin
//	zatn <= !(|hostslot_cnt) && zreq && !hostena;
////	zreq <= zce && !hostena;
//	cpureq1 <= (slot2_type == IDLE || slot2_bank != cpuAddr_mangled[24:23]) ? 1'b1 : 1'b0;
//end

//// sdram control ////
// Address bits will be allocated as follows:
// 24 downto 23: bank
// 22 downto 10: row
// 9 downto 1: column
always @ (posedge sysclk) begin
	sdata                       <= 16'bzzzzzzzzzzzzzzzz;

	if(!reset) begin
		refresh_pending           <= #1 1'b0;
		slot1_type                <= #1 IDLE;
		slot2_type                <= #1 IDLE;
		refreshcnt                <= #1 'd50;
	end
	sd_cmd                      <= #1 CMD_INHIBIT;
	sdaddr                      <= #1 13'b0;
	ba                          <= #1 2'b00;
	dqm                         <= #1 2'b00;
	cache_fill_1                <= #1 1'b0;
	cache_fill_2                <= #1 1'b0;
	if(!init_done) begin
		if(sdram_state == ph1) begin
			case(initstate)
				4'b0010 : begin // PRECHARGE
					sdaddr[10]          <= #1 1'b1; // all banks
					sd_cmd              <= #1 CMD_PRECHARGE;
				end
				4'b0011,
				4'b0100,
				4'b0101,
				4'b0110,
				4'b0111,
				4'b1000,
				4'b1001,
				4'b1010,
				4'b1011,
				4'b1100 : begin // AUTOREFRESH
					sd_cmd              <= #1 CMD_AUTO_REFRESH;
				end
				4'b1101 : begin // LOAD MODE REGISTER
					sd_cmd              <= #1 CMD_LOAD_MODE;
					//sdaddr              <= #1 13'b0001000100010; // BURST=4 LATENCY=2
					//sdaddr              <= #1 13'b0001000110010; // BURST=4 LATENCY=3
					//sdaddr              <= #1 13'b0001000110000; // noBURST LATENCY=3
					sdaddr              <= #1 13'b0001000110011; // BURST=8 LATENCY=3, no write bursts
				end
				default : begin
					// NOP
				end
			endcase
		end
	end else begin
		// Time slot control
		case(sdram_state)
			ph0 : begin
				cache_fill_2          <= #1 1'b1; // slot 2
				if(slot2_write) begin // Write cycle
					sdaddr[12:3]        <= #1 {1'b0, 1'b0, 1'b0, 1'b0, slot2_addr[9:4]}; // Can't auto-precharge, since we need to interrupt the burst
					sdaddr[2:0]         <= #1 slot2_addr[3:1];
					sdata               <= #1 writebufferWR_reg;
					ba                  <= #1 slot2_bank;
					sd_cmd              <= #1 CMD_WRITE;
					dqm                 <= #1 slot2_dqm;
					writebuffer_hold    <= #1 1'b0; // indicate to WriteBuffer that it's safe to accept the next write
				end
			end

			ph1 : begin
				cache_fill_2          <= #1 1'b1; // slot 2
				slot1_write           <= #1 1'b0;
				slot1_type            <= #1 IDLE;
				if(|hostslot_cnt) begin
					hostslot_cnt        <= #1 hostslot_cnt - 8'd1;
				end
				if(~|refreshcnt) begin
					refresh_pending     <= #1 1'b1;
				end else begin
					refreshcnt          <= #1 refreshcnt - 9'd1;
				end
				// we give the chipset first priority
				// (this includes anything on the "motherboard" - chip RAM, slow RAM and Kickstart, turbo modes notwithstanding)
				if(!chip_dma || !chipRW) begin
					slot1_type          <= #1 CHIP;
					sdaddr              <= #1 chipAddr[22:10];
					ba                  <= #1 2'b00; // always bank zero for chipset accesses, so we can interleave Fast RAM access
					sd_cmd              <= #1 CMD_ACTIVE;
					slot1_bank          <= #1 2'b00;
					slot1_dqm           <= #1 {chipU,chipL};
					slot1_dqm2          <= #1 2'b11;
					slot1_addr          <= #1 {1'b0, chipAddr, 1'b0};
					slot1_write         <= #1 !chipRW;
				end
				// next in line is refresh
				// (a refresh cycle blocks both access slots)
				else if(refresh_pending && slot2_type == IDLE) begin
					sd_cmd              <= #1 CMD_AUTO_REFRESH;
					refreshcnt          <= #1 'd50;
					slot1_type          <= #1 REFRESH;
					refresh_pending     <= #1 1'b0;
				end
				// the Amiga CPU gets next bite of the cherry, unless the OSD CPU has been cycle-starved
				// request from write buffer
				else if(writebuffer_req && wb_slot1ok && !wb_reservertg) begin
					// We only yield to the OSD CPU if it's both cycle-starved and ready to go.
					slot1_type          <= #1 CPU_WRITECACHE;
					sdaddr              <= #1 writebufferAddr[22:10];
					ba                  <= #1 writebufferAddr[24:23];
					slot1_bank          <= #1 writebufferAddr[24:23];
					slot1_dqm           <= #1 writebuffer_dqm;
					slot1_dqm2          <= #1 writebuffer_dqm2;
					sd_cmd              <= #1 CMD_ACTIVE;
					slot1_addr          <= #1 {writebufferAddr[24:1], 1'b0};
					slot1_write         <= #1 1'b1;
					writebufferWR_reg   <= #1 writebufferWR;
					writebufferWR2_reg  <= #1 writebufferWR2;
					writebuffer_hold    <= #1 1'b1; // let the write buffer know we're about to write
				end
				// request from read cache
				else if(cache_req && cpu_slot1ok && !cpu_reservertg) begin 
					// we only yield to the OSD CPU if it's both cycle-starved and ready to go
					slot1_type          <= #1 CPU_READCACHE;
					sdaddr              <= #1 cpuAddr_r[22:10];
					ba                  <= #1 cpuAddr_r[24:23];
					slot1_bank          <= #1 cpuAddr_r[24:23];
					slot1_dqm           <= #1 {cpuU,cpuL};
					sd_cmd              <= #1 CMD_ACTIVE;
					slot1_addr          <= #1 {cpuAddr_r[24:1], 1'b0};
				end
				else if(aud_slot1req) begin
					slot1_type          <= #1 AUDIO;
					sdaddr              <= #1 audAddr[22:10];
					ba                  <= #1 2'b00;	// Always bank zero for audio
					slot1_bank          <= #1 2'b00;
					slot1_dqm           <= #1 2'b00;
					slot1_dqm2          <= #1 2'b00;
					sd_cmd              <= #1 CMD_ACTIVE;
					slot1_addr          <= #1 audAddr;
				end
				else if(zreq) begin
					hostslot_cnt        <= #1 8'b00001111;
					slot1_type          <= #1 HOST;
					sdaddr              <= #1 zmAddr[22:10];
					ba                  <= #1 2'b00;
					// Always bank zero for SPI host CPU
					slot1_bank          <= #1 2'b00;
					slot1_dqm           <= #1 {!hostbytesel[0],!hostbytesel[1]};
					slot1_dqm2          <= #1 {!hostbytesel[2],!hostbytesel[3]};
					sd_cmd              <= #1 CMD_ACTIVE;
					slot1_addr          <= #1 {zmAddr,2'b00};
					slot1_write         <= #1 hostwe;
				end
			end

			ph2 : begin
				if(slot2_write) begin // Write cycle (2nd word)
					sdaddr[12:3]        <= #1 {1'b0, 1'b0, 1'b1, 1'b0, slot2_addr[9:4]}; // auto-precharge
					sdaddr[2:0]         <= #1 slot2_addr[3:1] + 1'd1;
					sdata               <= #1 writebufferWR2_reg;
					ba                  <= #1 slot2_bank;
					dqm                 <= #1 slot2_dqm2;
					sd_cmd              <= #1 CMD_WRITE;
				end
				// slot 2
				cache_fill_2                <= #1 1'b1;
			end

			ph3 : begin
				// slot 2
				cache_fill_2                <= #1 1'b1;
			end

			ph4 : begin
				cache_fill_2                <= #1 1'b1;
				if(slot1_type!=IDLE && slot1_type!=REFRESH && !slot1_write) begin // Read cycle
					ba                  <= #1 slot1_bank;
					sd_cmd              <= #1 CMD_READ;
					sdaddr              <= #1 {1'b0, 1'b0, 1'b1, 1'b0, slot1_addr[9:1]}; // AUTO PRECHARGE
				end
			end

			ph5 : begin
				cache_fill_2                <= #1 1'b1;
			end

			ph6 : begin
				cache_fill_2                <= #1 1'b1;
			end

			ph7 : begin
				cache_fill_2                <= #1 1'b1;
			end

			ph8 : begin
				if(slot1_write) begin // Write cycle
					sdaddr[12:3]        <= #1 {1'b0, 1'b0, 1'b0, 1'b0, slot1_addr[9:4]}; // Can't auto-precharge, since we need to interrupt the burst
					sdaddr[2:0]         <= #1 slot1_addr[3:1];
					ba                  <= #1 slot1_bank;
					dqm                 <= #1 slot1_dqm;
					sd_cmd              <= #1 CMD_WRITE;
					case (slot1_type)
						CHIP:           sdata   <= #1 chipWR;
						CPU_WRITECACHE:	sdata   <= #1 writebufferWR_reg;
						default :       sdata   <= #1 hostWR[31:16];
					endcase
					writebuffer_hold    <= #1 1'b0; // indicate to WriteBuffer that it's safe to accept the next write
				end
				cache_fill_1          <= #1 1'b1;
			end

			ph9 : begin
				cache_fill_1          <= #1 1'b1;

				// Access slot 2, RAS
				slot2_type            <= #1 IDLE;
				slot2_write           <= #1 1'b0;

				if(rtgce && rtg_slot2ok) begin 
					slot2_type        <= #1 RTG;
					sdaddr            <= #1 rtgAddr[22:10];
					ba                <= #1 rtgAddr[24:23];
					slot2_bank        <= #1 rtgAddr[24:23];
					slot2_dqm         <= #1 2'b11;
					sd_cmd            <= #1 CMD_ACTIVE;
					slot2_addr        <= #1 rtgAddr[24:0];
				end
				else if(writebuffer_req && wb_slot2ok) begin
					// We only yield to the OSD CPU if it's both cycle-starved and ready to go.
					slot2_type        <= #1 CPU_WRITECACHE;
					sdaddr            <= #1 writebufferAddr[22:10];
					ba                <= #1 writebufferAddr[24:23];
					slot2_bank        <= #1 writebufferAddr[24:23];
					slot2_dqm         <= #1 writebuffer_dqm;
					slot2_dqm2        <= #1 writebuffer_dqm2;
					sd_cmd            <= #1 CMD_ACTIVE;
					slot2_addr        <= #1 {writebufferAddr[24:1], 1'b0};
					slot2_write       <= #1 1'b1;
					writebufferWR_reg <= #1 writebufferWR;
					writebufferWR2_reg <= #1 writebufferWR2;
					writebuffer_hold  <= #1 1'b1; // let the write buffer know we're about to write
				end
				// request from read cache
				else if(cache_req && cpu_slot2ok) begin
					slot2_type        <= #1 CPU_READCACHE;
					sdaddr            <= #1 cpuAddr_r[22:10];
					ba                <= #1 cpuAddr_r[24:23];
					slot2_bank        <= #1 cpuAddr_r[24:23];
					slot2_dqm         <= #1 {cpuU, cpuL};
					slot2_addr        <= #1 {cpuAddr_r[24:1], 1'b0};
					sd_cmd            <= #1 CMD_ACTIVE;
				end

			end

			ph10 : begin
				if(slot1_write) begin // Write cycle (2nd word)
					sdaddr[12:3]    <= #1 {1'b0, 1'b0, 1'b1, 1'b0, slot1_addr[9:4]}; // auto-precharge
					sdaddr[2:0]     <= #1 slot1_addr[3:1] + 1'd1;
					ba              <= #1 slot1_bank;
					case (slot1_type)
						CPU_WRITECACHE:	sdata           <= #1 writebufferWR2_reg;
						default :       sdata           <= #1 hostWR[15:0];
					endcase
					sd_cmd              <= #1 CMD_WRITE;
					dqm                 <= #1 slot1_dqm2;
				end
				cache_fill_1          <= #1 1'b1;
			end

			ph11 : begin
				cache_fill_1          <= #1 1'b1;
			end

			// slot 2 CAS
			ph12 : begin
				cache_fill_1          <= #1 1'b1;
				if (slot2_type!=IDLE && !slot2_write) begin // Read cycle
					sdaddr              <= #1 {1'b0, 1'b0, 1'b1, 1'b0, slot2_addr[9:1]}; // AUTO PRECHARGE
					ba                  <= #1 slot2_bank;
					sd_cmd              <= #1 CMD_READ;
				end
			end

			ph13 : begin
				cache_fill_1          <= #1 1'b1;
			end

			ph14 : begin
				cache_fill_1          <= #1 1'b1;
			end

			ph15 : begin
				cache_fill_1          <= #1 1'b1;
			end

			default : begin
			end

		endcase
	end
end

//// Access slots ////

// We have two slots which can operate concurrently as long as they're accessing
// different banks. A refresh cycle on slot 1 finishes quickly enough that it need
// not block slot 2.

// The read burst size is 8-words, write burst is single. Writing the 2nd word is
// done by issuing a second write command.

//	      Slot 1 read         Slot 1 write           Slot 2 read         Slot 2 write
//
// ph0  read7                                                          CAS (1st word)
// ph1  Slot alloc, RAS (both R & W)                read0
// ph2                                              read1              CAS (2nd word)
// ph3                                              read2
// ph4   CAS, auto p/c                              read3
// ph5                                              read4
// ph6                                              read5
// ph7                                              read6
// ph8                       CAS (1st word)         read7
// ph9   read0                                      Slot alloc, RAS (both R & W)
// ph10  read1               CAS (2nd word)
// ph11  read2
// ph12  read3                                      CAS, auto p/c
// ph13  read4
// ph14  read5
// ph15  read6


endmodule

