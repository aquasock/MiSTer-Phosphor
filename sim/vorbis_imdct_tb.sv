`timescale 1ns/1ps
module vorbis_imdct_tb;
 reg clk=0,reset=1,spectrum_valid=0,start=0,sample_ready=1,long_block=0;
 reg [9:0] spectrum_index=0;reg signed [31:0] spectrum_value=0;
 wire spectrum_ready,sample_valid,ready,done,error;wire [10:0] sample_index;wire signed [31:0] sample_value;
 always #5 clk=~clk;
 vorbis_imdct dut(.clk(clk),.reset(reset),.spectrum_valid(spectrum_valid),.spectrum_ready(spectrum_ready),
  .spectrum_index(spectrum_index),.spectrum_value(spectrum_value),.start(start),.long_block(long_block),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_index(sample_index),.sample_value(sample_value),
  .ready(ready),.done(done),.error(error));
 integer i,j,count=0;integer expected,limit,tolerance,tone_bin=0;integer pattern_mode=0;real angle,ideal;
 always @(posedge clk)if(sample_valid&&sample_ready)begin
  count<=count+1;limit=long_block?1024:128;tolerance=long_block?12000:1200;
  angle=3.141592653589793/limit*(sample_index+0.5+limit/2.0)*(tone_bin+0.5);
  if(pattern_mode)begin
   ideal=0.0;
   for(j=0;j<limit;j=j+1)begin
    angle=3.141592653589793/limit*(sample_index+0.5+limit/2.0)*(j+0.5);
    ideal=ideal+(((j*73)%257)-128)*512.0*$cos(angle);
   end
   tolerance=long_block?120000:12000;
  end else ideal=65536.0*$cos(angle);
  expected=$rtoi(ideal+(ideal>=0?0.5:-0.5));
  if(sample_value<expected-tolerance||sample_value>expected+tolerance)
   $fatal(1,"sample %0d expected %0d got %0d",sample_index,expected,sample_value);
 end
 initial begin
  repeat(3)@(negedge clk);reset=0;
  for(i=0;i<128;i=i+1)begin
   @(negedge clk);spectrum_valid=1;spectrum_index=i;spectrum_value=i==0?65536:0;
  end
  @(negedge clk);spectrum_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error||count!=256)$fatal(1,"result error=%0d count=%0d",error,count);
  count=0;tone_bin=7;
  for(i=0;i<128;i=i+1)begin
   @(negedge clk);spectrum_valid=1;spectrum_index=i;spectrum_value=i==tone_bin?65536:0;
  end
  @(negedge clk);spectrum_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error||count!=256)$fatal(1,"tone result error=%0d count=%0d",error,count);
  count=0;pattern_mode=1;tone_bin=0;
  for(i=0;i<128;i=i+1)begin
   @(negedge clk);spectrum_valid=1;spectrum_index=i;spectrum_value=(((i*73)%257)-128)*512;
  end
  @(negedge clk);spectrum_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error||count!=256)$fatal(1,"full-spectrum result error=%0d count=%0d",error,count);
  count=0;pattern_mode=0;tone_bin=0;long_block=1;
  for(i=0;i<1024;i=i+1)begin
   @(negedge clk);spectrum_valid=1;spectrum_index=i;spectrum_value=i==0?65536:0;
  end
  @(negedge clk);spectrum_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error||count!=2048)$fatal(1,"long result error=%0d count=%0d",error,count);
  count=0;pattern_mode=1;
  for(i=0;i<1024;i=i+1)begin
   @(negedge clk);spectrum_valid=1;spectrum_index=i;spectrum_value=(((i*73)%257)-128)*512;
  end
  @(negedge clk);spectrum_valid=0;start=1;@(negedge clk);start=0;
  wait(done||error);if(error||count!=2048)$fatal(1,"long full-spectrum result error=%0d count=%0d",error,count);
  $display("PASS 256/2048-point IMDCTs against direct cosine definition");$finish;
 end
 initial begin repeat(300000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
