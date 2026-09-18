`timescale 1ns/1ps
module vorbis_synthesis_tb;
 reg clk=0,reset=1,start=0,workspace_read_data_valid=0,pcm_ready=1;
 wire workspace_read_valid;wire [11:0] workspace_read_address;reg signed [31:0] workspace_read_data=0;
 wire pcm_valid,ready,done,error;wire [10:0] pcm_index;wire signed [31:0] pcm_left,pcm_right;
 always #5 clk=~clk;
 vorbis_synthesis dut(.clk(clk),.reset(reset),.start(start),.long_block(1'b0),
  .previous_short(1'b1),.next_short(1'b1),.spectral_bins(11'd128),
  .workspace_read_valid(workspace_read_valid),.workspace_read_ready(1'b1),
  .workspace_read_address(workspace_read_address),.workspace_read_data_valid(workspace_read_data_valid),
  .workspace_read_data(workspace_read_data),.pcm_valid(pcm_valid),.pcm_ready(pcm_ready),
  .pcm_index(pcm_index),.pcm_left(pcm_left),.pcm_right(pcm_right),.ready(ready),.done(done),.error(error));
 always @(posedge clk)begin
  workspace_read_data_valid<=workspace_read_valid;
  if(workspace_read_valid)begin
   if(workspace_read_address==0)workspace_read_data<=65536;
   else if(workspace_read_address==1)workspace_read_data<=-65536;
   else workspace_read_data<=0;
  end
 end
 integer count=0;
 always @(posedge clk)if(pcm_valid&&pcm_ready)begin
  if(pcm_index!==count)$fatal(1,"PCM index expected %0d got %0d",count,pcm_index);
  if(pcm_left+pcm_right>1200||pcm_left+pcm_right< -1200)
   $fatal(1,"stereo mismatch index=%0d left=%0d right=%0d",pcm_index,pcm_left,pcm_right);
  count<=count+1;
 end
 task run_block;begin
  @(negedge clk);while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;
  while(done)@(negedge clk);while(!done&&!error)@(negedge clk);if(error)$fatal(1,"synthesis error");
 end endtask
 initial begin
  repeat(3)@(negedge clk);reset=0;
  run_block();if(count!=0)$fatal(1,"priming block emitted %0d samples",count);
  run_block();if(count!=128)$fatal(1,"second block emitted %0d samples",count);
  $display("PASS shared stereo IMDCT, window history, and synchronized PCM output");$finish;
 end
 initial begin repeat(100000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
