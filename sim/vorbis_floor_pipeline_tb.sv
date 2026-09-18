`timescale 1ns/1ps
module vorbis_floor_pipeline_tb;
 reg clk=0,reset=1,audio_packet_start=0;always #5 clk=~clk;
 wire [7:0] channels=2;wire [6:0] mode_count=1;wire [63:0] mode_blockflags=0;wire [511:0] mode_mappings=0;
 reg [63:0] reservoir=0;reg [6:0] bits_available=0;wire [31:0] bits=reservoir[31:0];
 wire consume_valid;wire [5:0] consume_count;
 wire [5:0] mapping_query;wire mapping_channel_query;wire [2:0] mapping_submap_query;
 wire [3:0] mapping_query_mux=0;wire [7:0] mapping_query_floor=0;
 wire [5:0] floor_query;wire [4:0] floor_part_query;wire [3:0] floor_class_query;
 wire [2:0] floor_subbook_query;wire [6:0] floor_x_query;
 wire [15:0] floor_query_type=1;wire [4:0] floor_query_partitions=1;wire [3:0] floor_query_partition_class=0;
 wire [3:0] floor_query_class_dimensions=1;wire [2:0] floor_query_class_subclasses=1;
 wire [7:0] floor_query_class_masterbook=2;
 wire [7:0] floor_query_subbook=floor_subbook_query==0?3:8'hff;
 wire [2:0] floor_query_multiplier=4;wire [3:0] floor_query_rangebits=4;
 reg [15:0] floor_query_x;always @* case(floor_x_query)0:floor_query_x=0;1:floor_query_x=16;default:floor_query_x=8;endcase
 wire prefix_lookup_valid;wire [5:0] prefix_lookup_book;wire [7:0] prefix_lookup_bits;
 reg prefix_result_valid=0,prefix_hit=1;reg [5:0] prefix_length=0;reg [17:0] prefix_symbol=0;
 wire [7:0] codebook_query;wire [13:0] active_query_address;
 wire [13:0] codebook_query_start=14'd0;wire [13:0] codebook_query_end=14'd1;
 wire [31:0] active_query_entry=32'd0;wire [31:0] active_query_codeword=32'd0;
 wire packet_floors_done;wire [1:0] channel_floor_present;wire point_valid;reg point_ready=1;
 wire [5:0] packet_mode;wire blockflag,previous_window,next_window;
 wire floor_channel;wire [6:0] point_index;wire [15:0] point_x;wire [8:0] point_y;wire point_active,error;
 wire packet_buffered_end=1'b0;wire packet_exhausted;
 vorbis_floor_pipeline dut(.*);
 integer points=0;
 always @(posedge clk)begin
  if(consume_valid)begin reservoir<=reservoir>>consume_count;bits_available<=bits_available-consume_count;end
  prefix_result_valid<=prefix_lookup_valid;
  if(prefix_lookup_valid)begin
   prefix_hit<=1;
   if(prefix_lookup_book==2)begin prefix_length<=1;prefix_symbol<=0;end
   else if(prefix_lookup_book==3)begin prefix_length<=2;prefix_symbol<=4;end
   else begin prefix_hit<=0;prefix_length<=0;prefix_symbol<=0;end
  end
  if(point_valid)begin
   if(point_index==2&&(point_y!=22||!point_active))$fatal(1,"channel %0d midpoint y=%0d active=%0d",floor_channel,point_y,point_active);
   points<=points+1;
  end
 end
 initial begin
  repeat(4)@(posedge clk);reset=0;
  // header=0; each channel: present=1,Y0=10,Y1=30,master code 0,subbook code 01.
  @(negedge clk);reservoir=64'd0 | (64'd1<<1)|(64'd10<<2)|(64'd30<<8)|(64'd0<<14)|(64'd1<<15)
   |(64'd1<<17)|(64'd10<<18)|(64'd30<<24)|(64'd0<<30)|(64'd1<<31);
  bits_available=40;audio_packet_start=1;@(negedge clk);audio_packet_start=0;
  repeat(1000)begin @(negedge clk);if(packet_floors_done)begin
   if(error||channel_floor_present!=2'b11||points!=6)$fatal(1,"pipeline error=%0d present=%b points=%0d",error,channel_floor_present,points);
   $display("PASS live stereo Floor-1 pipeline with prefix Huffman symbols");$finish;
  end end
  $fatal(1,"pipeline timeout control=%0d floor=%0d reader=%0d",dut.control.state,dut.floor.state,dut.reader.state);
 end
endmodule
