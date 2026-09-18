// Applies the Vorbis window to one channel and overlaps consecutive blocks.
// The emitted span is previous_N/4 + current_N/4, including correctly aligned
// 256<->2048 transitions. The first block primes the overlap store.
module vorbis_window_overlap(
 input wire clk,input wire reset,
 input wire block_start,input wire long_block,input wire previous_short,input wire next_short,
 input wire sample_valid,output wire sample_ready,input wire [10:0] sample_index,
 input wire signed [31:0] sample_value,
 output reg pcm_valid=0,input wire pcm_ready,output reg [10:0] pcm_index=0,
 output reg signed [31:0] pcm_value=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,LOAD=1,LOAD_WRITE=2,EMIT_INIT=3,EMIT_READ=4,EMIT_SUM=5,FINISH=6,
  LOAD_STORE=7,WINDOW_WAIT=8,EMIT_WAIT=9;
 reg [3:0] state=IDLE;reg current_bank=0,have_previous=0;
 reg [11:0] current_n=0,previous_n=0,left_begin=0,left_end=0,right_begin=0,right_end=0;
 reg [11:0] output_length=0,t=0;reg signed [12:0] current_start=0;
 reg signed [63:0] window_product;
 reg signed [31:0] previous_q=0,current_q=0,saved_sample=0,windowed=0;
 reg [10:0] saved_index=0;reg [11:0] ln=0,rn=0;reg [31:0] coefficient=0;
 wire [10:0] window_address=(saved_index>=right_begin?(rn==2048?0:1024):(ln==2048?0:1024))+
  (saved_index>=right_begin?right_end-1-saved_index:saved_index-left_begin);
 wire [31:0] window_q;
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(1152),.ADDR_WIDTH(11),
  .INIT_FILE("rtl/audio/vorbis/vorbis_window.mif"),
  .SIM_INIT_FILE("rtl/audio/vorbis/vorbis_window.hex")) window(clk,
  1'b0,11'd0,32'd0,window_address,window_q);
 wire bank_write=state==LOAD_STORE;
 wire [10:0] previous_address=previous_n/2+t;
 wire signed [12:0] current_position=$signed({1'b0,t})+current_start;
 wire previous_in_range=previous_address<previous_n;
 wire current_in_range=current_position>=0&&current_position<current_n;
 wire [10:0] current_address=current_position[10:0];
 wire [10:0] bank0_read_address=current_bank?previous_address:current_address;
 wire [10:0] bank1_read_address=current_bank?current_address:previous_address;
 wire [31:0] bank0_q,bank1_q;
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(2048),.ADDR_WIDTH(11)) bank0(clk,
  bank_write&&!current_bank,saved_index,windowed,bank0_read_address,bank0_q);
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(2048),.ADDR_WIDTH(11)) bank1(clk,
  bank_write&&current_bank,saved_index,windowed,bank1_read_address,bank1_q);
 assign ready=state==IDLE;
 assign sample_ready=state==LOAD;
 function signed [31:0] sat33;input signed [32:0] value;begin
  if(value>33'sh07fffffff)sat33=32'sh7fffffff;
  else if(value< -33'sh080000000)sat33=32'sh80000000;
  else sat33=value[31:0];
 end endfunction
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;pcm_valid<=0;done<=0;error<=0;have_previous<=0;current_bank<=0;end
  else begin
   done<=0;if(pcm_valid&&pcm_ready)pcm_valid<=0;
   case(state)
    IDLE:if(block_start)begin
     error<=0;current_n<=long_block?2048:256;
     ln<=long_block?(previous_short?256:2048):256;
     rn<=long_block?(next_short?256:2048):256;
     left_begin<=(long_block?512:64)-(long_block?(previous_short?64:512):64);
     left_end<=(long_block?512:64)+(long_block?(previous_short?64:512):64);
     right_begin<=(long_block?1536:192)-(long_block?(next_short?64:512):64);
     right_end<=(long_block?1536:192)+(long_block?(next_short?64:512):64);
     state<=LOAD;
    end
    LOAD:if(sample_valid&&sample_ready)begin
     saved_sample<=sample_value;saved_index<=sample_index;
     if(sample_index>=left_begin&&sample_index<left_end)
      coefficient<=0;
     else if(sample_index>=left_end&&sample_index<right_begin)coefficient<=32'h7fffffff;
     else if(sample_index>=right_begin&&sample_index<right_end)
      coefficient<=0;
     else coefficient<=0;
     state<=WINDOW_WAIT;
    end
    WINDOW_WAIT:state<=LOAD_WRITE;
    LOAD_WRITE:begin
     if(saved_index>=left_begin&&saved_index<left_end)coefficient=window_q;
     else if(saved_index>=left_end&&saved_index<right_begin)coefficient=32'h7fffffff;
     else if(saved_index>=right_begin&&saved_index<right_end)coefficient=window_q;
     else coefficient=0;
     window_product=$signed(saved_sample)*$signed({1'b0,coefficient});windowed=window_product>>>31;
     state<=LOAD_STORE;
    end
    LOAD_STORE:begin
     if(saved_index+1'b1==current_n)state<=EMIT_INIT;
     else if(saved_index>=current_n)begin error<=1;state<=FINISH;end
     else state<=LOAD;
    end
    EMIT_INIT:begin
     if(!have_previous)begin
      have_previous<=1;previous_n<=current_n;current_bank<=!current_bank;state<=FINISH;
     end else begin
      output_length<=(previous_n>>2)+(current_n>>2);current_start<=$signed({1'b0,current_n>>2})-$signed({1'b0,previous_n>>2});
      t<=0;pcm_index<=0;state<=EMIT_READ;
     end
    end
    EMIT_READ:state<=EMIT_WAIT;
    EMIT_WAIT:begin
     previous_q<=previous_in_range?$signed(current_bank?bank0_q:bank1_q):0;
     current_q<=current_in_range?$signed(current_bank?bank1_q:bank0_q):0;
     state<=EMIT_SUM;
    end
    EMIT_SUM:if(!pcm_valid)begin
     pcm_index<=t;pcm_value<=sat33($signed({previous_q[31],previous_q})+$signed({current_q[31],current_q}));pcm_valid<=1;
     if(t+1'b1==output_length)begin previous_n<=current_n;current_bank<=!current_bank;state<=FINISH;end
     else begin t<=t+1'b1;state<=EMIT_READ;end
    end
    FINISH:if(!pcm_valid)begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
