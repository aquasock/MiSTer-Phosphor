// Exact native 16-bit stereo I2S from a 512*Fs clock (22.5792 MHz for CD).
// Shared PCM tokens allow a later WAV adapter to use the same output path.
// This is the unfiltered digital boundary; system output selection/muting and
// analog/SPDIF/filter integration are separate from this serializer.
module media_pcm_i2s(
 input wire clk,reset,cancel,start,paused,
 input wire[35:0] start_position,
 input wire input_valid,input_eof,
 input wire signed[15:0] input_left,input_right,
 output wire input_ready,
 output reg i2s_bclk,i2s_lrclk,i2s_data,
 output wire[35:0] position,
 output reg finished,
 output wire error,
 output wire signed[15:0] pcm_output_left,pcm_output_right,
 output wire idle
);
 reg[8:0] phase;
 reg paused_latched;
 reg[15:0] left,right;
 wire signed[15:0] audio_left,audio_right;
 wire sink_finished;
 reg quiet=0;
 assign idle=(reset||cancel)||(quiet&&paused);
 assign pcm_output_left=audio_left;assign pcm_output_right=audio_right;
 media_pcm_sink sink(.clk(clk),.reset(reset),.cancel(cancel),.start(start),.start_position(start_position),
  .paused(paused_latched),.sample_tick(phase==0),.input_valid(input_valid),.input_eof(input_eof),
  .input_left(input_left),.input_right(input_right),.input_ready(input_ready),
  .audio_left(audio_left),.audio_right(audio_right),.position(position),.active(),.finished(sink_finished),.error(error));
 always @(posedge clk)begin
  if(reset||cancel||start)begin
   phase<=0;paused_latched<=paused;left<=0;right<=0;
   i2s_bclk<=0;i2s_lrclk<=1;i2s_data<=0;finished<=0;quiet<=0;
  end else begin
   phase<=phase+1'b1;
   if(!paused)quiet<=0;else if(phase==16&&paused_latched)quiet<=1;
   // Fetch at phase 0; capture the sink's updated samples one full clock later.
   if(phase==1)begin left<=audio_left;right<=audio_right;end
   if(phase==511)paused_latched<=paused;
   if(phase[3:0]==0)begin
    i2s_bclk<=0;
    if(phase==0)begin i2s_lrclk<=0;i2s_data<=right[0];end
    else if(phase==256)begin i2s_lrclk<=1;i2s_data<=left[0];end
    else i2s_data<=phase[8]?right[4'd0-phase[7:4]]:left[4'd0-phase[7:4]];
   end else if(phase[3:0]==8)i2s_bclk<=1;
   // The EOF fetch overlaps transmission of the previous right-channel LSB.
   // Wait until that bit has been sampled before allowing clock/output handoff.
   if(sink_finished&&phase==16)finished<=1;
  end
 end
endmodule
