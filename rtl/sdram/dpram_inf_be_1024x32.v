// dpram_inf_be_1024x16.v
// 2015, rok.krajnc@gmail.com
// inferrable two-port memory with byte-enables

module dpram_inf_be_1024x32 (
  input  wire           clock,
  input  wire           wren_a,
  input  wire [  4-1:0] byteena_a,
  input  wire [ 10-1:0] address_a,
  input  wire [ 32-1:0] data_a,
  output reg  [ 32-1:0] q_a,
  input  wire           wren_b,
  input  wire [  4-1:0] byteena_b,
  input  wire [ 10-1:0] address_b,
  input  wire [ 32-1:0] data_b,
  output reg  [ 32-1:0] q_b
);

// memory
reg [8-1:0] mem0 [0:1024-1];
reg [8-1:0] mem1 [0:1024-1];
reg [8-1:0] mem2 [0:1024-1];
reg [8-1:0] mem3 [0:1024-1];

// port a
always @ (posedge clock) begin
  if (wren_a && byteena_a[0]) mem0[address_a] <= #1 data_a[ 8-1: 0];
  if (wren_a && byteena_a[1]) mem1[address_a] <= #1 data_a[16-1: 8];
  if (wren_a && byteena_a[2]) mem2[address_a] <= #1 data_a[24-1:16];
  if (wren_a && byteena_a[3]) mem3[address_a] <= #1 data_a[32-1:24];
  q_a[ 8-1: 0] <= #1 mem0[address_a];
  q_a[16-1: 8] <= #1 mem1[address_a];
  q_a[24-1:16] <= #1 mem2[address_a];
  q_a[32-1:24] <= #1 mem3[address_a];
end

// port b
always @ (posedge clock) begin
  if (wren_b && byteena_b[0]) mem0[address_b] <= #1 data_b[ 8-1: 0];
  if (wren_b && byteena_b[1]) mem1[address_b] <= #1 data_b[16-1: 8];
  if (wren_b && byteena_b[2]) mem2[address_b] <= #1 data_b[24-1:16];
  if (wren_b && byteena_b[3]) mem3[address_b] <= #1 data_b[32-1:24];
  q_b[ 8-1: 0] <= #1 mem0[address_b];
  q_b[16-1: 8] <= #1 mem1[address_b];
  q_b[24-1:16] <= #1 mem2[address_b];
  q_b[32-1:24] <= #1 mem3[address_b];
end

endmodule

