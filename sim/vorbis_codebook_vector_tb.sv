`timescale 1ns/1ps
module vorbis_codebook_vector_tb;
 reg clk=0,reset=1,start=0;always #5 clk=~clk;
 reg [7:0] book=0;reg [17:0] entry=5;wire [7:0] codebook_query;
 wire [15:0] codebook_dimensions=2;wire [1:0] codebook_lookup_type=1;wire codebook_sequence=1;
 wire [31:0] codebook_minimum=0,codebook_delta=(32'd788<<21)|1;
 wire [13:0] codebook_multiplicand_start=0;wire [13:0] codebook_multiplicand_count=3;wire [13:0] multiplicand_query_address;
 reg [15:0] multiplicand_query_data;always @* case(multiplicand_query_address)0:multiplicand_query_data=2;1:multiplicand_query_data=4;default:multiplicand_query_data=6;endcase
 wire ready,value_valid,done,error;reg value_ready=1;wire [15:0] value_index;wire signed [31:0] value;
 vorbis_codebook_vector dut(.*);
 integer values=0;
 always @(posedge clk)if(value_valid)begin
  if(values==0&&(value_index!=0||value!=32'sd393216))$fatal(1,"value0 index=%0d value=%0d",value_index,value);
  if(values==1&&(value_index!=1||value!=32'sd655360))$fatal(1,"value1 index=%0d value=%0d",value_index,value);
  values<=values+1;
 end
 initial begin
  repeat(4)@(posedge clk);reset=0;@(negedge clk);start=1;@(negedge clk);start=0;
  repeat(100)begin @(negedge clk);if(done)begin
   if(error||values!=2)$fatal(1,"result error=%0d values=%0d",error,values);
   $display("PASS lookup-1 VQ expansion and sequence accumulation");$finish;
  end end
  $fatal(1,"vector timeout state=%0d",dut.state);
 end
endmodule
