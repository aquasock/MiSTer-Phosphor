`timescale 1ns/1ps
module vorbis_floor1_unpack_tb;
 reg clk=0,reset=1,start=0;always #5 clk=~clk;
 wire [5:0] floor_query;wire [4:0] floor_part_query;wire [3:0] floor_class_query;
 wire [2:0] floor_subbook_query;wire [6:0] floor_x_query;
 wire [15:0] floor_query_type=1;
 wire [4:0] floor_query_partitions=1;
 wire [3:0] floor_query_partition_class=0;
 wire [3:0] floor_query_class_dimensions=1;
 wire [2:0] floor_query_class_subclasses=0;
 wire [7:0] floor_query_class_masterbook=8'hff,floor_query_subbook=8'hff;
 wire [2:0] floor_query_multiplier=4;
 wire [3:0] floor_query_rangebits=4;
 reg [15:0] floor_query_x;
 always @* case(floor_x_query)0:floor_query_x=0;1:floor_query_x=16;default:floor_query_x=8;endcase
 reg [31:0] bits=0;reg [6:0] bits_available=0;wire bits_valid=bits_available!=0;
 wire consume_valid;wire [5:0] consume_count;
 wire huffman_valid;reg huffman_ready=1;wire [7:0] huffman_book;reg symbol_valid=0;reg [17:0] symbol=0;
 wire ready,done,present,error,point_valid;reg point_ready=1;wire [6:0] point_index;wire [15:0] point_x;wire [8:0] point_y;wire point_active;
 vorbis_floor1_unpack dut(.*,.floor_number(6'd0));
 integer points=0;
 always @(posedge clk)begin
  if(consume_valid)begin bits<=bits>>consume_count;bits_available<=bits_available-consume_count;end
  if(point_valid)begin
   case(points)
    0:if(point_index!=0||point_x!=0||point_y!=10||!point_active)$fatal(1,"point0 %0d/%0d/%0d/%0d",point_index,point_x,point_y,point_active);
    1:if(point_index!=1||point_x!=16||point_y!=30||!point_active)$fatal(1,"point1 %0d/%0d/%0d/%0d",point_index,point_x,point_y,point_active);
    2:if(point_index!=2||point_x!=8||point_y!=20||point_active)$fatal(1,"point2 %0d/%0d/%0d/%0d",point_index,point_x,point_y,point_active);
   endcase
   points<=points+1;
  end
 end
 initial begin
  repeat(4)@(posedge clk);reset=0;
  // presence=1, Y0=10, Y1=30, subclass book unused => raw Y2=0.
  @(negedge clk);bits=1|(10<<1)|(30<<7);bits_available=13;start=1;
  @(negedge clk);start=0;
  repeat(100)begin @(posedge clk);if(done)begin
   if(error||!present||points!=3)$fatal(1,"done error=%0d present=%0d points=%0d",error,present,points);
   $display("PASS Floor-1 reconstructed endpoints and inactive midpoint");$finish;
  end end
  $fatal(1,"Floor-1 timeout state=%0d",dut.state);
 end
endmodule
