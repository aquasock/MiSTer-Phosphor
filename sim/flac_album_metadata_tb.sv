`timescale 1ns/1ps
module flac_album_metadata_tb;
 reg write_clk=0,read_clk=0,reset=1,new_file=0,enabled=1,byte_valid=0;
 reg [7:0] byte_data=0;reg [13:0] read_address=0;reg [6:0] current_track=1;
 wire [7:0] read_data;wire valid,artwork_valid,current_title_long;wire [6:0] track_count;
 flac_album_metadata dut(.*);
 always #5 write_clk=~write_clk;
 always #7 read_clk=~read_clk;
 task put(input [7:0] value);begin @(negedge write_clk);byte_data=value;byte_valid=1;@(negedge write_clk);byte_valid=0;end endtask
 integer i;
 initial begin
  repeat(2)@(negedge write_clk);reset=0;
  put("f");put("L");put("a");put("C");
  // Last APPLICATION block, 11,704 bytes.
  put(8'h82);put(8'h00);put(8'h2d);put(8'hb8);
  put("M");put("P");put("3");put("A");put(1);put(6);put(1);put(0);
  put("A");put("L");put("B");put("U");put("M");
  for(i=13;i<11704;i=i+1)put(i==103?1:0);
  repeat(3)@(negedge write_clk);
  if(!valid||!artwork_valid||track_count!=6||!current_title_long)$fatal(1,"metadata header was not published");
  read_address=8;repeat(2)@(negedge read_clk);if(read_data!="A")$fatal(1,"RAM read mismatch");
  read_address=12;repeat(2)@(negedge read_clk);if(read_data!="M")$fatal(1,"RAM tail mismatch");
  $display("PASS");$finish;
 end
endmodule
