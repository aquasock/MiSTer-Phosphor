`timescale 1ns/1ps
module vorbis_residue_vector_task_tb;
 reg clk=0,reset=1,task_valid=0,write_ready=1,prefix_result_valid=0;
 wire task_ready,consume_valid,prefix_lookup_valid,write_valid,done,error;
 wire [5:0] consume_count,prefix_lookup_book;wire [7:0] prefix_lookup_bits,codebook_query;
 wire [13:0] active_query_address,multiplicand_query_address;
 wire [23:0] write_address;wire signed [31:0] write_value;
 integer count=0;reg signed [31:0] expected;
 always #5 clk=~clk;
 function [31:0] packed_float;input [20:0] mantissa;input [9:0] exponent;begin
  packed_float={1'b0,exponent,mantissa};
 end endfunction
 wire [15:0] multiplicand_query_data=(multiplicand_query_address==0)?2:
  (multiplicand_query_address==1)?4:6;

 vorbis_residue_vector_task dut(.clk(clk),.reset(reset),
  .packet_buffered_end(1'b0),.exhausted(),
  .task_valid(task_valid),.task_ready(task_ready),.task_book(8'd3),
  .task_offset(24'd100),.task_length(24'd6),.bits(32'h55),.bits_available(7'd32),
  .consume_valid(consume_valid),.consume_count(consume_count),
  .prefix_lookup_valid(prefix_lookup_valid),.prefix_lookup_book(prefix_lookup_book),
  .prefix_lookup_bits(prefix_lookup_bits),.prefix_result_valid(prefix_result_valid),
  .prefix_hit(1'b1),.prefix_length(6'd1),.prefix_symbol(18'd5),
  .codebook_query(codebook_query),.codebook_query_start(14'd0),.codebook_query_end(14'd1),
  .codebook_dimensions(16'd2),.codebook_lookup_type(2'd1),.codebook_sequence(1'b1),
  .codebook_minimum(packed_float(0,788)),.codebook_delta(packed_float(1,788)),
  .codebook_multiplicand_start(14'd0),.codebook_multiplicand_count(14'd3),
  .active_query_address(active_query_address),.active_query_entry(32'd0),
  .active_query_codeword(32'd0),.multiplicand_query_address(multiplicand_query_address),
  .multiplicand_query_data(multiplicand_query_data),.write_valid(write_valid),
  .write_ready(write_ready),.write_address(write_address),.write_value(write_value),
  .done(done),.error(error));

 always @(posedge clk)begin
  prefix_result_valid<=prefix_lookup_valid;
  if(write_valid&&write_ready)begin
   expected=(count%2==0)?32'sh00060000:32'sh000a0000;
   if(write_address!==100+count||write_value!==expected)begin
    $display("FAIL write %0d address=%0d value=%h",count,write_address,write_value);$finish;
   end
   count<=count+1;
  end
 end
 initial begin
  repeat(3)@(posedge clk);reset<=0;@(posedge clk);
  task_valid<=1;@(posedge clk);while(!task_ready)@(posedge clk);task_valid<=0;
  wait(done||error);@(posedge clk);
  if(error||count!=6)begin $display("FAIL done error=%0d count=%0d",error,count);$finish;end
  $display("PASS residue task decoded three symbols into six type-2 writes");$finish;
 end
 initial begin repeat(1000)@(posedge clk);$display("FAIL timeout");$finish;end
endmodule
