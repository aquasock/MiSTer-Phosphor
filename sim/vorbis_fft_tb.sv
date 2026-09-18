`timescale 1ns/1ps
module vorbis_fft_tb;
 reg clk=0,reset=1,load_valid=0,start=0,output_request=0;
 reg [10:0] load_address=0,output_address=0;reg signed [23:0] load_real=0,load_imag=0;
 reg [3:0] length_log2=7;
 wire load_ready,output_valid,ready,done,error;wire signed [23:0] output_real,output_imag;
 always #5 clk=~clk;
 vorbis_fft dut(.*);
 integer i,j,expected_r,expected_i,fetch_tolerance=3;real angle,ideal_r,ideal_i;
 function [10:0] reverse11;input [10:0] value;integer b;begin
  reverse11=0;for(b=0;b<11;b=b+1)reverse11[10-b]=value[b];
 end endfunction
 task fetch;input [10:0] address;input signed [23:0] expected_real;input signed [23:0] expected_imag;begin
  @(negedge clk);output_address=address;output_request=1;@(negedge clk);output_request=0;
  while(!output_valid)@(negedge clk);
  if(output_real<expected_real-fetch_tolerance||output_real>expected_real+fetch_tolerance||output_imag<expected_imag-fetch_tolerance||output_imag>expected_imag+fetch_tolerance)
   $fatal(1,"bin %0d expected=%0d,%0d real=%0d imag=%0d",address,expected_real,expected_imag,output_real,output_imag);
 end endtask
 initial begin
  repeat(3)@(negedge clk);reset=0;
  for(i=0;i<128;i=i+1)begin
   @(negedge clk);load_valid=1;load_address=i;load_real=i==0?24'sh010000:0;load_imag=0;
  end
  @(negedge clk);load_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error)$fatal(1,"FFT error");
  fetch(0,512,0);fetch(1,512,0);fetch(63,512,0);fetch(127,512,0);
  for(i=0;i<128;i=i+1)begin
   @(negedge clk);load_valid=1;load_address=i;load_real=i==64?24'sh010000:0;load_imag=0;
  end
  @(negedge clk);load_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error)$fatal(1,"FFT tone error");
  fetch(0,512,0);fetch(32,0,512);fetch(64,-512,0);fetch(96,0,-512);
  length_log2=11;fetch_tolerance=128;
  for(i=0;i<2048;i=i+1)begin
   @(negedge clk);load_valid=1;load_address=reverse11(i);
   load_real=((i*73)%257)-128;load_imag=((i*29)%127)-63;
  end
  @(negedge clk);load_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error)$fatal(1,"2048-point FFT error");
  for(i=0;i<32;i=i+1)begin
   output_address=i*61;ideal_r=0.0;ideal_i=0.0;
   for(j=0;j<2048;j=j+1)begin
    angle=2.0*3.141592653589793*j*output_address/2048.0;
    ideal_r=ideal_r+((((j*73)%257)-128)*$cos(angle)-(((j*29)%127)-63)*$sin(angle))/2048.0;
    ideal_i=ideal_i+((((j*73)%257)-128)*$sin(angle)+(((j*29)%127)-63)*$cos(angle))/2048.0;
   end
   expected_r=$rtoi(ideal_r+(ideal_r>=0?0.5:-0.5));expected_i=$rtoi(ideal_i+(ideal_i>=0?0.5:-0.5));
   fetch(output_address,expected_r,expected_i);
  end
  $display("PASS normalized 128-point inverse FFT impulse and complex tone");$finish;
 end
 initial begin repeat(500000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
