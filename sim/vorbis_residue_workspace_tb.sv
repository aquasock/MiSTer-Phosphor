`timescale 1ns/1ps
module vorbis_residue_workspace_tb;
 reg clk=0,reset=1,clear_start=0,add_valid=0,read_valid=0,set_valid=0;
 reg [4:0] clear_length=0;reg [3:0] add_address=0,read_address=0;
 reg signed [31:0] add_value=0;
 wire set_ready;wire [3:0] set_address=0;wire signed [31:0] set_value=0;
 wire clear_ready,clear_done,add_ready,read_ready,read_data_valid;
 wire signed [31:0] read_data;
 always #5 clk=~clk;
 vorbis_residue_workspace #(.ADDRESS_WIDTH(4)) dut(.*);
 task clear;input [4:0] length;begin
  while(!clear_ready)@(negedge clk);clear_length=length;clear_start=1;
  @(negedge clk);clear_start=0;while(clear_done)@(negedge clk);while(!clear_done)@(negedge clk);
 end endtask
 task add;input [3:0] address;input signed [31:0] value;begin
  while(!add_ready)@(negedge clk);add_address=address;add_value=value;add_valid=1;
  @(negedge clk);add_valid=0;
 end endtask
 task check;input [3:0] address;input signed [31:0] expected;begin
  while(!read_ready)@(negedge clk);read_address=address;read_valid=1;
  @(negedge clk);read_valid=0;while(read_data_valid)@(negedge clk);while(!read_data_valid)@(negedge clk);
  if(read_data!==expected)$fatal(1,"address %0d expected %h got %h",address,expected,read_data);
 end endtask
 initial begin
  repeat(3)@(negedge clk);reset=0;
  clear(8);add(3,32'sh00018000);add(3,-32'sh00004000);add(7,32'sh00020000);
  check(3,32'sh00014000);check(7,32'sh00020000);check(2,0);
  clear(8);check(3,0);check(7,0);
  $display("PASS residue workspace clear, accumulate, and readback");$finish;
 end
 initial begin repeat(500)@(posedge clk);$fatal(1,"timeout state=%0d clear_index=%0d",dut.state,dut.clear_index);end
endmodule
