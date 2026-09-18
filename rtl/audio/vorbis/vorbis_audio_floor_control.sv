// Decodes an audio packet's mode/window header from the shared reservoir and
// dispatches the configured Floor-1 submap once for each supported channel.
module vorbis_audio_floor_control(
 input wire clk,input wire reset,input wire audio_packet_start,input wire [7:0] channels,
 input wire [6:0] mode_count,input wire [63:0] mode_blockflags,input wire [511:0] mode_mappings,
 input wire [31:0] bits,input wire [6:0] bits_available,
 output reg consume_valid=0,output reg [5:0] consume_count=0,
 output reg [5:0] mapping_query=0,output reg mapping_channel_query=0,
 input wire [3:0] mapping_query_mux,input wire [7:0] mapping_query_floor,
 output reg [2:0] mapping_submap_query=0,
 output reg floor_start=0,input wire floor_ready,output reg [5:0] floor_number=0,
 output reg floor_channel=0,input wire floor_done,input wire floor_present,
 output reg packet_floors_done=0,output reg [1:0] channel_floor_present=0,
 output reg [5:0] packet_mode=0,output reg blockflag=0,
 output reg previous_window=0,output reg next_window=0,output reg error=0
);
 localparam WAIT_PACKET=0,HEADER=1,HEADER_GAP=2,MAP_GAP=3,SUBMAP_GAP=4,
  FLOOR_LAUNCH=5,FLOOR_WAIT=6,FINISH=7,SUBMAP_READ=8;
 reg [3:0] state=WAIT_PACKET;
 reg channel_index=0;
 function [2:0] ilog_modes;input [6:0] count;integer i;reg [6:0] top;begin
  top=count-1'b1;ilog_modes=0;for(i=0;i<6;i=i+1)if(top[i])ilog_modes=i+1;
 end endfunction
 wire [2:0] mode_bits=ilog_modes(mode_count);
 wire [6:0] mode_mask=mode_bits==0?0:((7'd1<<mode_bits)-1'b1);
 wire [5:0] selected_mode=(bits>>1)&mode_mask;
 wire selected_long=mode_blockflags[selected_mode];
 wire [5:0] header_length=1+mode_bits+(selected_long?2:0);
 always @(posedge clk)begin
  if(reset)begin state<=WAIT_PACKET;consume_valid<=0;floor_start<=0;packet_floors_done<=0;error<=0;end
  else begin
   consume_valid<=0;floor_start<=0;packet_floors_done<=0;
   case(state)
    WAIT_PACKET:if(audio_packet_start)begin channel_floor_present<=0;state<=HEADER;end
    HEADER:if(bits_available>=header_length)begin
     if(bits[0]||selected_mode>=mode_count)begin error<=1;state<=FINISH;end
     else begin
      packet_mode<=selected_mode;blockflag<=selected_long;
      previous_window<=selected_long?bits[1+mode_bits]:0;next_window<=selected_long?bits[2+mode_bits]:0;
      mapping_query<=mode_mappings[selected_mode*8 +: 8];consume_valid<=1;consume_count<=header_length;
      channel_index<=0;mapping_channel_query<=0;state<=HEADER_GAP;
     end
    end
    HEADER_GAP:state<=MAP_GAP;
    MAP_GAP:begin mapping_submap_query<=mapping_query_mux;state<=SUBMAP_GAP;end
    SUBMAP_GAP:state<=SUBMAP_READ;
    SUBMAP_READ:begin floor_number<=mapping_query_floor;floor_channel<=channel_index;state<=FLOOR_LAUNCH;end
    FLOOR_LAUNCH:if(floor_ready)begin floor_start<=1;state<=FLOOR_WAIT;end
    FLOOR_WAIT:if(floor_done)begin
     channel_floor_present[channel_index]<=floor_present;
     if(channel_index==channels-1'b1)state<=FINISH;
     else begin channel_index<=channel_index+1'b1;mapping_channel_query<=channel_index+1'b1;state<=MAP_GAP;end
    end
    FINISH:begin packet_floors_done<=1;state<=WAIT_PACKET;end
   endcase
  end
 end
endmodule
