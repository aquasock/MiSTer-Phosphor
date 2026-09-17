`timescale 1ns/1ps
module media_xy_interpolator_tb;
 reg clk=0,active=0,sample_tick=0;
 reg signed [15:0] sample_left=0,sample_right=0;
 wire output_tick;
 wire signed [15:0] output_left,output_right;
 integer inputs=0,outputs=0;
 always #25 clk=~clk;
 media_xy_interpolator dut(.*);
 always @(posedge clk)if(output_tick)begin
  outputs=outputs+1;
  if(outputs>16&&(output_left<9998||output_left>10002||output_right> -9998||output_right< -10002))begin
   $display("FAIL output %0d: %0d %0d",outputs,output_left,output_right);$fatal;
  end
 end
 initial begin
  repeat(4)@(posedge clk);active=1;sample_left=10000;sample_right=-10000;
  repeat(20)begin
   repeat(100)@(posedge clk);@(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;inputs=inputs+1;
  end
  repeat(100)@(posedge clk);
  if(outputs!=inputs*2)begin $display("FAIL ticks: in=%0d out=%0d",inputs,outputs);$fatal;end
  $display("PASS: %0d inputs produced %0d ordered 2x outputs",inputs,outputs);$finish;
 end
endmodule
