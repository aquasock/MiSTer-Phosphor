`timescale 1ns/1ps
module media_pcm_sink_recovery_tb;
reg clk=0,reset=1,cancel=0,start=0,paused=0,sample_tick=0;
reg input_valid=0,input_eof=0;
reg signed [15:0] input_left=0,input_right=0;
wire input_ready;
wire signed [15:0] audio_left,audio_right;
wire [35:0] position;
wire active,finished,error;
always #5 clk=~clk;

media_pcm_sink dut(
 .clk(clk),.reset(reset),.cancel(cancel),.start(start),.start_position(36'd0),
 .paused(paused),.sample_tick(sample_tick),.input_valid(input_valid),.input_eof(input_eof),
 .input_left(input_left),.input_right(input_right),.input_ready(input_ready),
 .audio_left(audio_left),.audio_right(audio_right),.position(position),
 .active(active),.finished(finished),.error(error)
);

task tick(input valid,input signed [15:0] left,right);
begin
 @(negedge clk);sample_tick=1;input_valid=valid;input_left=left;input_right=right;
 @(negedge clk);sample_tick=0;input_valid=0;
end
endtask

initial begin
 repeat(2)@(negedge clk);reset=0;start=1;
 @(negedge clk);start=0;
 tick(1,16'sd111,16'sd222);
 if(!active||audio_left!=111||audio_right!=222)$fatal(1,"initial PCM was not accepted");
 tick(0,0,0);
 if(!active||!error||audio_left!=0||audio_right!=0)$fatal(1,"underrun became fatal or was not reported");
 tick(1,-16'sd333,16'sd444);
 if(!active||audio_left!=-333||audio_right!=444)$fatal(1,"PCM did not recover after underrun");
 $display("PASS transient underrun remained active and recovered");
 $finish;
end
endmodule
