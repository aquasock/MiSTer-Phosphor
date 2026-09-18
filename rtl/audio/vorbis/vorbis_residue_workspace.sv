// Signed Q16.16 residue accumulation memory. A block is cleared serially,
// then each accepted contribution is added with a two-cycle read/modify/write
// transaction so Quartus can retain this storage in M10K RAM.
module vorbis_residue_workspace #(
 parameter ADDRESS_WIDTH=12
)(
 input wire clk,input wire reset,
 input wire clear_start,input wire [ADDRESS_WIDTH:0] clear_length,
 output wire clear_ready,output reg clear_done=0,
 input wire add_valid,output wire add_ready,
 input wire [ADDRESS_WIDTH-1:0] add_address,input wire signed [31:0] add_value,
 input wire set_valid,output wire set_ready,
 input wire [ADDRESS_WIDTH-1:0] set_address,input wire signed [31:0] set_value,
 input wire read_valid,output wire read_ready,input wire [ADDRESS_WIDTH-1:0] read_address,
 output reg read_data_valid=0,output reg signed [31:0] read_data=0
);
 localparam IDLE=0,CLEAR=1,ADD_READ=2,ADD_WRITE=3,READ_WAIT=4;
 reg [2:0] state=IDLE;
 reg [ADDRESS_WIDTH:0] clear_index=0,clear_limit=0;
 reg [ADDRESS_WIDTH-1:0] saved_address=0;
 reg signed [31:0] saved_value=0,ram_read=0;
 wire memory_write=(state==IDLE&&set_valid)||(state==CLEAR)||(state==ADD_WRITE);
 wire [ADDRESS_WIDTH-1:0] memory_write_address=state==CLEAR?clear_index[ADDRESS_WIDTH-1:0]:
  (state==ADD_WRITE?saved_address:set_address);
 wire [31:0] memory_write_data=state==CLEAR?32'd0:(state==ADD_WRITE?ram_read+saved_value:set_value);
 wire [ADDRESS_WIDTH-1:0] memory_read_address=state==IDLE?(add_valid?add_address:read_address):saved_address;
 wire [31:0] memory_read_data;
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(1<<ADDRESS_WIDTH),.ADDR_WIDTH(ADDRESS_WIDTH)) memory(clk,
  memory_write,memory_write_address,memory_write_data,memory_read_address,memory_read_data);

 assign clear_ready=state==IDLE;
 assign set_ready=state==IDLE&&!clear_start;
 assign add_ready=state==IDLE&&!clear_start&&!set_valid&&!read_valid;
 assign read_ready=state==IDLE&&!clear_start&&!set_valid&&!add_valid;

 always @(posedge clk)begin
  if(reset)begin state<=IDLE;clear_done<=0;read_data_valid<=0;end
  else begin
   clear_done<=0;read_data_valid<=0;
   case(state)
    IDLE:begin
     if(clear_start)begin
      clear_limit<=clear_length;clear_index<=0;
      if(clear_length==0)clear_done<=1;else state<=CLEAR;
     end else if(set_valid)begin
     end else if(add_valid)begin
      saved_address<=add_address;saved_value<=add_value;
      state<=ADD_READ;
     end else if(read_valid)begin
      saved_address<=read_address;state<=READ_WAIT;
     end
    end
    CLEAR:begin
     if(clear_index+1'b1>=clear_limit)begin clear_done<=1;state<=IDLE;end
     else clear_index<=clear_index+1'b1;
    end
    ADD_READ:begin ram_read<=memory_read_data;state<=ADD_WRITE;end
    ADD_WRITE:state<=IDLE;
    READ_WAIT:begin read_data<=memory_read_data;read_data_valid<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
