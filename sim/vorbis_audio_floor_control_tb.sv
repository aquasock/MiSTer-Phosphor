`timescale 1ns/1ps
module vorbis_audio_floor_control_tb;
 reg clk=0,reset=1,audio_packet_start=0;always #5 clk=~clk;
 wire [7:0] channels=2;wire [6:0] mode_count=2;wire [63:0] mode_blockflags=2'b10;
 wire [511:0] mode_mappings=512'h00000100;
 reg [31:0] bits=6;reg [6:0] bits_available=8;wire consume_valid;wire [5:0] consume_count;
 wire [5:0] mapping_query;wire mapping_channel_query;wire [3:0] mapping_query_mux=0;
 wire [7:0] mapping_query_floor=mapping_query;wire [2:0] mapping_submap_query;
 wire floor_start;reg floor_ready=1;wire [5:0] floor_number;wire floor_channel;
 reg floor_done=0;reg floor_present=1;wire packet_floors_done;wire [1:0] channel_floor_present;
 wire [5:0] packet_mode;wire blockflag,previous_window,next_window,error;
 vorbis_audio_floor_control dut(.*);
 integer launches=0;
 always @(posedge clk)begin
  floor_done<=floor_start;
  if(consume_valid)begin bits<=bits>>consume_count;bits_available<=bits_available-consume_count;end
  if(floor_start)begin
   if(floor_number!=1||floor_channel!=launches)$fatal(1,"launch %0d floor=%0d channel=%0d",launches,floor_number,floor_channel);
   launches<=launches+1;
  end
 end
 initial begin
  repeat(4)@(posedge clk);reset=0;@(negedge clk);audio_packet_start=1;@(negedge clk);audio_packet_start=0;
  repeat(50)begin @(negedge clk);if(packet_floors_done)begin
   if(error||packet_mode!=1||!blockflag||!previous_window||next_window||channel_floor_present!=2'b11||launches!=2)
    $fatal(1,"result error=%0d mode=%0d block=%0d windows=%0d/%0d present=%b launches=%0d",error,packet_mode,blockflag,previous_window,next_window,channel_floor_present,launches);
   $display("PASS audio mode mapped Floor-1 to both stereo channels");$finish;
  end end
  $fatal(1,"controller timeout state=%0d",dut.state);
 end
endmodule
