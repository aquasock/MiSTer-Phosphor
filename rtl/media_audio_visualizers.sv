// Parallel, latency-matched renderers share a read-only native PCM tap.
module media_audio_visualizers(
 input wire control_clk,input wire [1:0] select_visualizer,
 input wire audio_clk,video_clk,audio_active,sample_tick,
 input wire signed [15:0] sample_left,sample_right,
 input wire [23:0] rgb,input wire hs,vs,de,layout_de,
 output wire [23:0] rgb_out,output wire hs_out,vs_out,de_out
);
 wire [255:0] levels;
 media_audio_fft fft(.clk(audio_clk),.active(audio_active),.sample_tick(sample_tick),
  .sample_left(sample_left),.sample_right(sample_right),.levels(levels),.published());
 wire [256:0] spectrum;
 video_config_cdc #(.WIDTH(257)) spectrum_config(.src_clk(audio_clk),.dst_clk(video_clk),
  .src_data({audio_active,levels}),.dst_data(spectrum));
 wire [1:0] mode;
 video_config_cdc #(.WIDTH(2)) visualizer_mode_config(.src_clk(control_clk),.dst_clk(video_clk),.src_data(select_visualizer),.dst_data(mode));
 reg [32:0] xy_sample=0;
 always @(posedge audio_clk)begin
  if(!audio_active)xy_sample<=0;
  else if(sample_tick)xy_sample<={~xy_sample[32],sample_left,sample_right};
 end
 wire [32:0] xy_position;
 video_config_cdc #(.WIDTH(33)) xy_sample_config(.src_clk(audio_clk),.dst_clk(video_clk),.src_data(xy_sample),.dst_data(xy_position));
 reg vs_d=0;reg [1:0] frame_mode=0;reg [17:0] mode_pipe=0;
 always @(posedge video_clk)begin
  vs_d<=vs;if(vs&&!vs_d)frame_mode<=mode;
  mode_pipe<={mode_pipe[15:0],frame_mode};
 end
 wire [26:0] scope_pixel,fire_pixel,xy_pixel;
 media_waveform_visualizer scope(.audio_clk(audio_clk),.video_clk(video_clk),.audio_active(audio_active),.sample_tick(sample_tick),
  .sample_left(sample_left),.sample_right(sample_right),.rgb(rgb),.hs(hs),.vs(vs),.de(de),.layout_de(layout_de),
  .rgb_out(scope_pixel[23:0]),.hs_out(scope_pixel[26]),.vs_out(scope_pixel[25]),.de_out(scope_pixel[24]));
 media_fire_renderer fire(.clk(video_clk),.active(spectrum[256]),.levels(spectrum[255:0]),
  .rgb(rgb),.hs(hs),.vs(vs),.de(de),.layout_de(layout_de),
  .rgb_out(fire_pixel[23:0]),.hs_out(fire_pixel[26]),.vs_out(fire_pixel[25]),.de_out(fire_pixel[24]));
 media_xy_visualizer xy(.clk(video_clk),.active(spectrum[256]&&frame_mode==2),
  .sample_toggle(xy_position[32]),.sample_left(xy_position[31:16]),.sample_right(xy_position[15:0]),
  .rgb(rgb),.hs(hs),.vs(vs),.de(de),.layout_de(layout_de),
  .rgb_out(xy_pixel[23:0]),.hs_out(xy_pixel[26]),.vs_out(xy_pixel[25]),.de_out(xy_pixel[24]));
 assign {hs_out,vs_out,de_out,rgb_out}=mode_pipe[17:16]==2?xy_pixel:mode_pipe[17:16]==1?fire_pixel:scope_pixel;
endmodule
