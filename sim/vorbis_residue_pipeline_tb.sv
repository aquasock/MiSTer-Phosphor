`timescale 1ns/1ps
module vorbis_residue_pipeline_tb;
 reg clk=0,reset=1,start=0,prefix_result_valid=0,read_valid=0;
 reg [11:0] read_address=0;wire read_ready,read_data_valid,ready,done,error;
 wire signed [31:0] read_data;wire [5:0] class_query,prefix_lookup_book,consume_count;
 wire [2:0] pass_query;wire [7:0] prefix_lookup_bits,codebook_query;
 wire [13:0] active_query_address,multiplicand_query_address;
 wire prefix_lookup_valid,consume_valid;reg [17:0] returned_symbol=0;
 always #5 clk=~clk;
 function [31:0] packed_float;input [20:0] mantissa;input [9:0] exponent;begin
  packed_float={1'b0,exponent,mantissa};
 end endfunction
 wire [15:0] dimensions=(codebook_query==2)?1:2;
 wire [1:0] lookup_type=(codebook_query==10)?1:0;
 wire [15:0] multiplicand_data=(multiplicand_query_address==0)?2:
  (multiplicand_query_address==1)?4:6;

 vorbis_residue_pipeline dut(.clk(clk),.reset(reset),.start(start),.residue_type(16'd2),
  .workspace_length(13'd8),
  .packet_buffered_end(1'b0),
  .packet_exhausted(1'b0),
  .residue_begin(24'd0),.residue_end(24'd4),.partition_size(24'd4),
  .classifications(7'd1),.classbook(8'd2),.classbook_dimensions(8'd1),
  .class_query(class_query),.class_cascade(8'h01),.pass_query(pass_query),
  .pass_book(pass_query==0?8'd10:8'hff),.bits(32'h55),.bits_available(7'd32),
  .consume_valid(consume_valid),.consume_count(consume_count),
  .prefix_lookup_valid(prefix_lookup_valid),.prefix_lookup_book(prefix_lookup_book),
  .prefix_lookup_bits(prefix_lookup_bits),.prefix_result_valid(prefix_result_valid),
  .prefix_hit(1'b1),.prefix_length(6'd1),.prefix_symbol(returned_symbol),
  .codebook_query(codebook_query),.codebook_query_start(14'd0),.codebook_query_end(14'd1),
  .codebook_dimensions(dimensions),.codebook_lookup_type(lookup_type),.codebook_sequence(codebook_query==10),
  .codebook_minimum(packed_float(0,788)),.codebook_delta(packed_float(1,788)),
  .codebook_multiplicand_start(14'd0),.codebook_multiplicand_count(codebook_query==10?14'd3:14'd0),
  .active_query_address(active_query_address),.active_query_entry(32'd0),.active_query_codeword(32'd0),
  .multiplicand_query_address(multiplicand_query_address),.multiplicand_query_data(multiplicand_data),
  .read_valid(read_valid),.read_ready(read_ready),.read_address(read_address),
  .read_data_valid(read_data_valid),.read_data(read_data),
  .set_valid(1'b0),.set_ready(),.set_address(12'd0),.set_value(32'sd0),
  .ready(ready),.done(done),.error(error));

 always @(posedge clk)begin
  prefix_result_valid<=prefix_lookup_valid;
  if(prefix_lookup_valid)returned_symbol<=prefix_lookup_book==2?0:5;
 end
 task check;input [11:0] address;input signed [31:0] expected;begin
  @(negedge clk);while(!read_ready)@(negedge clk);read_address=address;read_valid=1;
  @(negedge clk);read_valid=0;while(read_data_valid)@(negedge clk);while(!read_data_valid)@(negedge clk);
  if(read_data!==expected)$fatal(1,"address %0d expected %h got %h",address,expected,read_data);
 end endtask
 initial begin
  repeat(4)@(negedge clk);reset=0;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done||error);if(error)$fatal(1,"pipeline error");
  check(0,32'sh00060000);check(1,32'sh000a0000);
  check(2,32'sh00060000);check(3,32'sh000a0000);
  $display("PASS scheduler, shared Huffman/VQ, and accumulating residue workspace");$finish;
 end
 initial begin repeat(2000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
