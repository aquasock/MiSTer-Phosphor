`timescale 1ns/1ps
module vorbis_unsigned_divider_tb;
 reg clk=0,reset=1,start=0;reg [17:0] numerator=0,denominator=1;always #5 clk=~clk;
 wire ready,done,error;wire [17:0] quotient,remainder;
 integer n,d,cases=0;
 vorbis_unsigned_divider #(.WIDTH(18),.TRIPLE_STEP(1)) dut(.*);
 task check;input [17:0] a,b;begin
  while(!ready)@(posedge clk);@(negedge clk);numerator=a;denominator=b;start=1;
  @(negedge clk);start=0;while(!done)@(posedge clk);#1;
  if(error||quotient!==a/b||remainder!==a%b)
   $fatal(1,"divide mismatch %0d/%0d q=%0d r=%0d",a,b,quotient,remainder);
  cases=cases+1;
 end endtask
 initial begin
  repeat(3)@(posedge clk);reset=0;
  for(d=1;d<64;d=d+1)begin
   check(0,d);check(d-1,d);check(d,d);check(d+1,d);
   check(18'h3ffff-d,d);check(18'h3ffff,d);
  end
  for(n=0;n<262144;n=n+7919)check(n,(n%63)+1);
  $display("PASS triple-step unsigned divider cases=%0d",cases);$finish;
 end
 initial begin repeat(100000)@(posedge clk);$fatal(1,"timeout");end
endmodule
