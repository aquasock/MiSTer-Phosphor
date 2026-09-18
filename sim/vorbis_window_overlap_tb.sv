`timescale 1ns/1ps
module vorbis_window_overlap_tb;
 reg clk=0,reset=1,block_start=0,long_block=0,previous_short=1,next_short=1;
 reg sample_valid=0,pcm_ready=1;reg [10:0] sample_index=0;reg signed [31:0] sample_value=0;
 wire sample_ready,pcm_valid,ready,done,error;wire [10:0] pcm_index;wire signed [31:0] pcm_value;
 always #5 clk=~clk;
 vorbis_window_overlap dut(.*);
 integer count=0,phase=0;reg signed [63:0] p0,p1;reg signed [31:0] expected;
 always @(posedge clk)if(pcm_valid&&pcm_ready)begin
  if(phase==2)begin
   p0=100000*$signed({1'b0,dut.window.memory[1024+127-pcm_index]});
   p1=200000*$signed({1'b0,dut.window.memory[1024+pcm_index]});expected=(p0>>>31)+(p1>>>31);
  end else if(phase==3&&pcm_index<128)begin
   p0=200000*$signed({1'b0,dut.window.memory[1024+127-pcm_index]});
   p1=300000*$signed({1'b0,dut.window.memory[1024+pcm_index]});expected=(p0>>>31)+(p1>>>31);
  end else if(phase==3)expected=(64'sd300000*32'h7fffffff)>>>31;
  else if(phase==4)begin
   p0=300000*$signed({1'b0,dut.window.memory[1023-pcm_index]});
   p1=400000*$signed({1'b0,dut.window.memory[pcm_index]});expected=(p0>>>31)+(p1>>>31);
  end else if(pcm_index<448)expected=(64'sd400000*32'h7fffffff)>>>31;
  else begin
   p0=400000*$signed({1'b0,dut.window.memory[1024+575-pcm_index]});
   p1=500000*$signed({1'b0,dut.window.memory[1024+pcm_index-448]});expected=(p0>>>31)+(p1>>>31);
  end
  if(pcm_value!==expected)$fatal(1,"phase %0d sample %0d expected %0d got %0d",phase,pcm_index,expected,pcm_value);
  count<=count+1;
 end
 task send_block;input is_long;input prev_short;input following_short;input signed [31:0] value;integer n,i;begin
  n=is_long?2048:256;while(!ready)@(negedge clk);long_block=is_long;previous_short=prev_short;next_short=following_short;
  block_start=1;@(negedge clk);block_start=0;
  for(i=0;i<n;i=i+1)begin
   while(!sample_ready)@(negedge clk);sample_index=i;sample_value=value;sample_valid=1;@(negedge clk);
  end
  sample_valid=0;while(done)@(negedge clk);while(!done&&!error)@(negedge clk);if(error)$fatal(1,"block error");
 end endtask
 initial begin
  repeat(3)@(negedge clk);reset=0;
  phase=1;send_block(0,1,1,100000);if(count!=0)$fatal(1,"first block emitted PCM");
  phase=2;send_block(0,1,1,200000);if(count!=128)$fatal(1,"short/short count %0d",count);
  count=0;phase=3;send_block(1,1,0,300000);if(count!=576)$fatal(1,"short/long count %0d",count);
  count=0;phase=4;send_block(1,0,1,400000);if(count!=1024)$fatal(1,"long/long count %0d",count);
  count=0;phase=5;send_block(0,1,1,500000);if(count!=576)$fatal(1,"long/short count %0d",count);
  $display("PASS all Vorbis window overlap size transitions");$finish;
 end
 initial begin repeat(30000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
