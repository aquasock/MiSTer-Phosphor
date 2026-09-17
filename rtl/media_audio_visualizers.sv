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
 wire [1:0] audio_mode;
 video_config_cdc #(.WIDTH(2)) visualizer_audio_mode_config(.src_clk(control_clk),.dst_clk(audio_clk),.src_data(select_visualizer),.dst_data(audio_mode));
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
 // Preserve every O-Scope point in order. The former coalescing mailbox and
 // one-entry pending register could discard intermediate samples, causing
 // conspicuous long catch-up lines. This FIFO never backpressures audio; in
 // the unlikely event it fills, only visualization samples are discarded.
 wire xy_active=spectrum[256]&&frame_mode==2;
 wire xy_interpolated_tick;
 wire signed [15:0] xy_interpolated_left,xy_interpolated_right;
 media_xy_interpolator xy_interpolator(
  .clk(audio_clk),.active(audio_active&&audio_mode==2),.sample_tick(sample_tick),
  .sample_left(sample_left),.sample_right(sample_right),
  .output_tick(xy_interpolated_tick),
  .output_left(xy_interpolated_left),.output_right(xy_interpolated_right));
 wire [31:0] xy_fifo_q;
 wire xy_fifo_empty,xy_fifo_full,xy_sample_ready;
 wire xy_fifo_read=xy_active&&xy_sample_ready&&!xy_fifo_empty;
 dcfifo #(
  .lpm_numwords(256),.lpm_showahead("ON"),.lpm_type("dcfifo"),
  .lpm_width(32),.lpm_widthu(8),.overflow_checking("ON"),
  .underflow_checking("ON"),.use_eab("ON"),
  .rdsync_delaypipe(4),.wrsync_delaypipe(4),
  .write_aclr_synch("ON"),.read_aclr_synch("ON")
 ) xy_sample_fifo(
  // Flush while another visualizer is selected so changing to XY begins at
  // the live audio position rather than draining stale queued samples.
  .aclr(!audio_active||mode!=2),.data({xy_interpolated_left,xy_interpolated_right}),
  .wrclk(audio_clk),.wrreq(xy_interpolated_tick&&!xy_fifo_full),.wrfull(xy_fifo_full),
  .rdclk(video_clk),.rdreq(xy_fifo_read),.q(xy_fifo_q),.rdempty(xy_fifo_empty)
 );
 media_xy_visualizer xy(.clk(video_clk),.active(xy_active),
  .sample_valid(!xy_fifo_empty),.sample_ready(xy_sample_ready),
  .sample_left(xy_fifo_q[31:16]),.sample_right(xy_fifo_q[15:0]),
  .rgb(rgb),.hs(hs),.vs(vs),.de(de),.layout_de(layout_de),
  .rgb_out(xy_pixel[23:0]),.hs_out(xy_pixel[26]),.vs_out(xy_pixel[25]),.de_out(xy_pixel[24]));
 assign {hs_out,vs_out,de_out,rgb_out}=mode_pipe[17:16]==2?xy_pixel:mode_pipe[17:16]==1?fire_pixel:scope_pixel;
endmodule
