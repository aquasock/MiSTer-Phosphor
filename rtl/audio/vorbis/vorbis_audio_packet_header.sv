// Vorbis audio-packet front end. This validates the audio packet flag and
// resolves its mode, block size and long-window neighbor flags. The payload
// remains untouched for the floor/residue engine which follows this stage.
module vorbis_audio_packet_header(
 input wire clk,input wire reset,input wire setup_valid,
 input wire [6:0] mode_count,input wire [63:0] mode_blockflags,
 input wire [511:0] mode_mappings,
 input wire packet_valid,input wire [7:0] packet_data,
 input wire packet_start,input wire packet_end,output wire packet_ready,
 output reg header_valid=0,output reg error=0,
 output reg [5:0] mode=0,output reg blockflag=0,
 output reg previous_window=0,output reg next_window=0,
 output reg [7:0] mapping=0
);
 reg [1:0] packet_number=0;
 reg waiting_second=0;
 reg [7:0] first_byte=0;
 reg [5:0] pending_mode=0;
 function [2:0] ilog_modes;input [6:0] count;integer i;reg [6:0] top;begin
  top=count-1'b1;ilog_modes=0;for(i=0;i<6;i=i+1)if(top[i])ilog_modes=i+1;
 end endfunction
 wire [2:0] mode_bits=ilog_modes(mode_count);
 wire [6:0] shifted_mode={1'b0,packet_data[7:1]};
 wire [6:0] mode_mask=mode_bits==0?0:((7'd1<<mode_bits)-1'b1);
 wire [5:0] candidate_mode=shifted_mode&mode_mask;
 wire candidate_long=mode_blockflags[candidate_mode];
 wire needs_second=candidate_long&&(mode_bits==6);
 assign packet_ready=1'b1;

 always @(posedge clk)begin
  if(reset)begin
   packet_number<=0;waiting_second<=0;header_valid<=0;error<=0;
   mode<=0;blockflag<=0;previous_window<=0;next_window<=0;mapping<=0;
  end else begin
   header_valid<=0;
   if(packet_valid)begin
    if(packet_start)begin
     waiting_second<=0;
     if(packet_number==3&&setup_valid)begin
      first_byte<=packet_data;
      if(packet_data[0]||candidate_mode>=mode_count)error<=1;
      else if(needs_second)begin
       if(packet_end)error<=1;else begin waiting_second<=1;pending_mode<=candidate_mode;end
      end
      else begin
       mode<=candidate_mode;blockflag<=candidate_long;
       mapping<=mode_mappings[candidate_mode*8 +: 8];
       previous_window<=candidate_long?packet_data[1+mode_bits]:0;
       next_window<=candidate_long?packet_data[2+mode_bits]:0;
       header_valid<=1;
      end
     end
    end else if(waiting_second)begin
     mode<=pending_mode;blockflag<=1;mapping<=mode_mappings[pending_mode*8 +: 8];
     previous_window<=first_byte[7];next_window<=packet_data[0];header_valid<=1;waiting_second<=0;
    end
    if(packet_end&&packet_number<3)packet_number<=packet_number+1'b1;
   end
  end
 end
endmodule
