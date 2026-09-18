`timescale 1ns/1ps
module media_album_ui_toggle_tb;
 reg clk=0,reset=1,new_file=0,enabled=1,osd_open=0;
 reg [10:0] key=0;
 wire visible;
 media_album_ui_toggle dut(.*);
 always #5 clk=~clk;
 task key_event(input press,input [8:0] code);begin
  @(negedge clk);key={~key[10],press,code};@(negedge clk);
 end endtask
 initial begin
  repeat(2)@(negedge clk);reset=0;
  key_event(1,9'h03a);if(!visible)$fatal(1,"M press did not show UI");
  key_event(1,9'h03a);if(!visible)$fatal(1,"typematic repeat toggled UI");
  key_event(0,9'h03a);key_event(1,9'h03a);if(visible)$fatal(1,"second press did not hide UI");
  key_event(0,9'h03a);osd_open=1;key_event(1,9'h03a);if(visible)$fatal(1,"OSD press leaked");
  key_event(0,9'h03a);osd_open=0;key_event(1,9'h03a);if(!visible)$fatal(1,"post-OSD press ignored");
  new_file=1;@(negedge clk);new_file=0;if(visible)$fatal(1,"new file did not hide UI");
  enabled=0;key_event(1,9'h03a);if(visible)$fatal(1,"disabled UI toggled");
  $display("PASS");$finish;
 end
endmodule
