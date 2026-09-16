// Codec-independent signed stereo PCM sink in the selected audio clock domain.
// sample_tick is the serializer's once-per-frame fetch request, not a clock.
// FIFO tokens are either stereo samples or an EOF marker after the last sample.
// The caller must reset/drain its CDC FIFO before start/cancel/file replacement.
// start_position is a source-sample index (44.1 kHz for initial music profile).
module media_pcm_sink (
 input wire clk,reset,cancel,start,
 input wire [35:0] start_position,
 input wire paused,sample_tick,
 input wire input_valid,input_eof,
 input wire signed [15:0] input_left,input_right,
 output wire input_ready,
 output wire signed [15:0] audio_left,audio_right,
 output reg [35:0] position,
 output reg active,finished,error
);
 reg have_sample,started;
 reg signed [15:0] held_left,held_right;
 assign input_ready=active&&!paused&&sample_tick&&!reset&&!cancel&&!start;
 assign audio_left=(active&&!paused&&!reset&&!cancel)?held_left:16'sd0;
 assign audio_right=(active&&!paused&&!reset&&!cancel)?held_right:16'sd0;
 always @(posedge clk) begin
  if(reset||cancel) begin
   position<=0;active<=0;finished<=0;error<=0;
   have_sample<=0;started<=0;held_left<=0;held_right<=0;
  end else if(start) begin
   position<=start_position;active<=1;finished<=0;error<=0;
   have_sample<=0;started<=0;held_left<=0;held_right<=0;
  end else if(input_ready) begin
   // The preceding sample has occupied one output interval. Advance only
   // when that interval completes, including the tick consuming EOF.
   if(have_sample)position<=position+1'b1;
   if(input_valid) begin
    if(input_eof) begin
     active<=0;finished<=1;have_sample<=0;held_left<=0;held_right<=0;
    end else begin
     held_left<=input_left;held_right<=input_right;
     have_sample<=1;started<=1;
    end
   end else begin
    held_left<=0;held_right<=0;have_sample<=0;
    // Permit initial prefill; after the first sample, starvation is a
    // functional playback failure, not an invisible inserted silence sample.
    if(started)begin active<=0;error<=1;end
   end
  end
 end
endmodule
