`timescale 1ns/1ps
module vorbis_huffman_reader_tb;
 reg clk=0,reset=1;always #5 clk=~clk;
 reg request_valid=0;wire request_ready;reg [7:0] request_book=0;
 reg [31:0] bits=0;reg [6:0] bits_available=0;wire consume_valid;wire [5:0] consume_count;
 wire prefix_lookup_valid;wire [5:0] prefix_lookup_book;wire [7:0] prefix_lookup_bits;
 reg prefix_result_valid=0,prefix_hit=0;reg [5:0] prefix_length=0;reg [17:0] prefix_symbol=0;
 wire [7:0] codebook_query;reg [13:0] codebook_query_start=0,codebook_query_end=1;
 wire [13:0] active_query_address;reg [31:0] active_query_entry=0,active_query_codeword=0;
 wire symbol_valid;reg symbol_ready=1;wire [17:0] symbol;wire [5:0] symbol_length;wire error;
 reg use_prefix=1;
 integer cycles=0;always @(posedge clk)begin cycles<=cycles+1;if(cycles==1000)$fatal(1,"watch state=%0d scalar=%0d bit=%0d avail=%0d pvalid=%0d presult=%0d",dut.state,dut.scalar.state,dut.fallback_bit,bits_available,prefix_lookup_valid,prefix_result_valid);end
 wire packet_buffered_end=0;wire exhausted;vorbis_huffman_reader dut(.*);
 always @(posedge clk)begin
  prefix_result_valid<=prefix_lookup_valid;
  if(prefix_lookup_valid)begin
   prefix_hit<=use_prefix;prefix_length<=5;prefix_symbol<=18'd5;
  end
  active_query_entry<={8'd0,18'd7,6'd9};active_query_codeword<=32'h155;
  if(consume_valid)begin bits<=bits>>consume_count;bits_available<=bits_available-consume_count;end
 end
 task request_and_check;input [31:0] word;input [6:0] available;input [17:0] expected_symbol;input [5:0] expected_length;begin
  @(negedge clk);bits=word;bits_available=available;request_valid=1;
  @(negedge clk);request_valid=0;
  while(!symbol_valid&&!error)@(negedge clk);
  if(error||symbol!=expected_symbol||symbol_length!=expected_length)
   $fatal(1,"reader got %0d/%0d expected %0d/%0d error=%0d",symbol,symbol_length,expected_symbol,expected_length,error);
  @(negedge clk);
  if(bits_available!=available-expected_length)$fatal(1,"consume left %0d expected %0d",bits_available,available-expected_length);
 end endtask
 initial begin
  repeat(4)@(posedge clk);reset=0;
  use_prefix=1;request_and_check(32'h0000001d,16,5,5);
  while(!request_ready)@(negedge clk);
  use_prefix=0;request_and_check(32'h00000155,16,7,9);
  $display("PASS Huffman reader prefix and canonical fallback paths");$finish;
 end
endmodule
