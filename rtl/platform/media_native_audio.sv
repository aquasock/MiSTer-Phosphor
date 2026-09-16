// Production CD PCM CDC, native clock and HDMI ownership/output handoff.
// Movie processing stays on movie_clock; only external output selection changes.
module media_native_audio(
 input wire refclk,config_clk,wr_clk,reset,movie_clock,
 input wire want_cd,paused,movie_96k,
 input wire[4:0] attenuation,
 input wire pcm_reset,pcm_valid,
 input wire[32:0] pcm_data,
 output wire pcm_ready,
 output wire cd_clock,
 output wire[35:0] position,
 output wire finished,error,
 output wire visual_active,visual_tick,
 output wire signed [15:0] visual_left,visual_right,
 input wire movie_bclk,movie_lrclk,movie_data,movie_spdif,movie_dac_l,movie_dac_r,
 output wire output_mclk,output_bclk,output_lrclk,output_data,output_spdif,output_dac_l,output_dac_r,
 input wire pad_scl,pad_sda,hps_scl_low,hps_sda_low,
 output wire hps_scl_in,hps_sda_in,drive_scl_low,drive_sda_low
);
 // Every new clock domain releases global reset on its own clock edges.
 (* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
 reg[2:0] ref_reset_sync=7,movie_reset_sync=7,out_reset_sync=7;
 always @(posedge refclk or posedge reset)if(reset)ref_reset_sync<=7;else ref_reset_sync<={ref_reset_sync[1:0],1'b0};
 always @(posedge movie_clock or posedge reset)if(reset)movie_reset_sync<=7;else movie_reset_sync<={movie_reset_sync[1:0],1'b0};
 always @(posedge output_mclk or posedge reset)if(reset)out_reset_sync<=7;else out_reset_sync<={out_reset_sync[1:0],1'b0};
 wire[7:0] cfg_ref,cfg_cd;
 video_config_cdc #(.WIDTH(8)) config_ref(.src_clk(config_clk),.dst_clk(refclk),.src_data({want_cd,paused,movie_96k,attenuation}),.dst_data(cfg_ref));
 video_config_cdc #(.WIDTH(8)) config_cd(.src_clk(config_clk),.dst_clk(cd_clock),.src_data({want_cd,paused,movie_96k,attenuation}),.dst_data(cfg_cd));
 wire select_cd,mute,cd_ready,config_error,cd_locked;
 media_audio_clocks clocks(.refclk(refclk),.reset(ref_reset_sync[2]),.movie_clock(movie_clock),.select_cd(select_cd),.enable(1'b1),
  .cd_clock(cd_clock),.cd_locked(cd_locked),.output_clock(output_mclk));
 // Ready comes from edges of the actual selected clock, with a matching mode
 // echo; neither a requested mode nor PLL lock alone acknowledges a handoff.
 (* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg[2:0] select_sync=0,lock_sync=0;
 reg clock_applied=0;reg[7:0] settle_count=0;
 always @(posedge output_mclk)begin
  if(out_reset_sync[2])begin select_sync<=0;lock_sync<=0;clock_applied<=0;settle_count<=0;end
  else begin
   select_sync<={select_sync[1:0],select_cd};lock_sync<={lock_sync[1:0],cd_locked};
   if(clock_applied!=select_sync[2])begin clock_applied<=select_sync[2];settle_count<=0;end
   else if(!clock_applied||lock_sync[2])begin if(!(&settle_count))settle_count<=settle_count+1'b1;end
   else settle_count<=0;
  end
 end
 wire[1:0] clock_status;
 video_config_cdc #(.WIDTH(2)) clock_ack(.src_clk(output_mclk),.dst_clk(refclk),
  .src_data({&settle_count,clock_applied}),.dst_data(clock_status));
 // Mute movie serial data at a channel-pair boundary, then acknowledge two
 // silent frames before allowing the external clock and stream to switch.
 (* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg[2:0] mute_movie_sync=0;
 reg old_movie_lr=0,movie_muted=0;reg[1:0] movie_quiet=0;
 always @(posedge movie_clock)begin
  mute_movie_sync<={mute_movie_sync[1:0],mute};old_movie_lr<=movie_lrclk;
  if(movie_reset_sync[2])begin movie_muted<=1;movie_quiet<=0;end
  else if(old_movie_lr&&!movie_lrclk)begin
   movie_muted<=mute_movie_sync[2];
   if(!mute_movie_sync[2])movie_quiet<=0;else if(movie_quiet!=3)movie_quiet<=movie_quiet+1'b1;
  end
 end
 wire movie_idle_ref,cd_idle_ref,cd_idle;
 video_config_cdc #(.WIDTH(1)) movie_idle_cdc(.src_clk(movie_clock),.dst_clk(refclk),.src_data(movie_muted&&movie_quiet>=2),.dst_data(movie_idle_ref));
 video_config_cdc #(.WIDTH(1)) cd_idle_cdc(.src_clk(cd_clock),.dst_clk(refclk),.src_data(cd_idle),.dst_data(cd_idle_ref));
 media_hdmi_audio_control #(.DRAIN_CYCLES(2048)) control(.clk(refclk),.reset(ref_reset_sync[2]),.want_cd(cfg_ref[7]),.movie_96k(cfg_ref[5]),
  .clients_idle(select_cd?cd_idle_ref:movie_idle_ref),.clock_ready(clock_status[1]),.clock_applied_cd(clock_status[0]),
  .clock_cd(select_cd),.mute(mute),.cd_ready(cd_ready),.error(config_error),
  .pad_scl(pad_scl),.pad_sda(pad_sda),.hps_scl_low(hps_scl_low),.hps_sda_low(hps_sda_low),
  .hps_scl_in(hps_scl_in),.hps_sda_in(hps_sda_in),.drive_scl_low(drive_scl_low),.drive_sda_low(drive_sda_low));
 wire[1:0] ready_cd;
 video_config_cdc #(.WIDTH(2)) ready_cdc(.src_clk(refclk),.dst_clk(cd_clock),.src_data({config_error,cd_ready}),.dst_data(ready_cd));
 wire fifo_reset=reset||pcm_reset;
 (* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg[2:0] wr_reset_sync=7,rd_reset_sync=7;
 always @(posedge wr_clk or posedge fifo_reset)if(fifo_reset)wr_reset_sync<=7;else wr_reset_sync<={wr_reset_sync[1:0],1'b0};
 always @(posedge cd_clock or posedge fifo_reset)if(fifo_reset)rd_reset_sync<=7;else rd_reset_sync<={rd_reset_sync[1:0],1'b0};
 wire fifo_full,fifo_empty,sink_ready;wire[32:0] fifo_q;
 assign pcm_ready=!fifo_full&&!wr_reset_sync[2]&&!fifo_reset;
 dcfifo #(.lpm_numwords(256),.lpm_showahead("ON"),.lpm_type("dcfifo"),.lpm_width(33),.lpm_widthu(8),
  .overflow_checking("ON"),.underflow_checking("ON"),.use_eab("ON"),.rdsync_delaypipe(4),.wrsync_delaypipe(4),
  .write_aclr_synch("ON"),.read_aclr_synch("ON")) pcm_fifo(
  .aclr(fifo_reset),.data(pcm_data),.wrclk(wr_clk),.wrreq(pcm_valid&&pcm_ready),.wrfull(fifo_full),
  .q(fifo_q),.rdclk(cd_clock),.rdreq(sink_ready&&!fifo_empty),.rdempty(fifo_empty));
 reg started=0;
 always @(posedge cd_clock)if(rd_reset_sync[2])started<=0;else started<=1;
 wire signed[15:0] source_left=fifo_q[31:16],source_right=fifo_q[15:0];
 wire signed[15:0] scaled_left=cfg_cd[4]?16'sd0:source_left>>>cfg_cd[3:0];
 wire signed[15:0] scaled_right=cfg_cd[4]?16'sd0:source_right>>>cfg_cd[3:0];
 wire cd_bclk,cd_lrclk,cd_data,cd_spdif,cd_dac_l,cd_dac_r,sink_finished,sink_error;
 wire signed[15:0] cd_left,cd_right;
 media_pcm_i2s sink(.clk(cd_clock),.reset(rd_reset_sync[2]),.cancel(1'b0),.start(!started&&!rd_reset_sync[2]),
  .paused(cfg_cd[6]||!cfg_cd[7]||!ready_cd[0]),.start_position(36'd0),
  .input_valid(!fifo_empty),.input_eof(fifo_q[32]),.input_left(scaled_left),.input_right(scaled_right),.input_ready(sink_ready),
  .i2s_bclk(cd_bclk),.i2s_lrclk(cd_lrclk),.i2s_data(cd_data),.position(position),.finished(sink_finished),.error(sink_error),
  .pcm_output_left(cd_left),.pcm_output_right(cd_right),.idle(cd_idle));
 // Read-only observation at the output sample boundary, after volume/mute.
 reg visual_lr=1;
 always @(posedge cd_clock)visual_lr<=cd_lrclk;
 assign visual_active=cfg_cd[7]&&!rd_reset_sync[2];
 assign visual_tick=visual_lr&&!cd_lrclk&&!rd_reset_sync[2];
 assign visual_left=cd_left;assign visual_right=cd_right;
 reg[1:0] spdif_div=0;
 always @(posedge cd_clock)if(rd_reset_sync[2])spdif_div<=0;else spdif_div<=spdif_div+1'b1;
 spdif #(.SAMPLE_RATE(44100)) music_spdif(.clk_i(cd_clock),.rst_i(rd_reset_sync[2]),.bit_out_en_i(spdif_div==0),.sample_i({cd_right,cd_left}),.spdif_o(cd_spdif),.sample_req_o());
 sigma_delta_dac #(15) music_dac_l(.CLK(cd_clock),.RESET(rd_reset_sync[2]),.DACin({~cd_left[15],cd_left[14:0]}),.DACout(cd_dac_l));
 sigma_delta_dac #(15) music_dac_r(.CLK(cd_clock),.RESET(rd_reset_sync[2]),.DACin({~cd_right[15],cd_right[14:0]}),.DACout(cd_dac_r));
 // Give every serializer two more complete sample intervals to retire EOF.
 reg[10:0] tail=0;
 always @(posedge cd_clock)if(rd_reset_sync[2]||!sink_finished)tail<=0;else if(!(&tail))tail<=tail+1'b1;
 assign finished=&tail;
 assign error=sink_error||ready_cd[1];
 assign output_bclk=select_cd?cd_bclk:movie_bclk;
 assign output_lrclk=select_cd?cd_lrclk:movie_lrclk;
 assign output_data=select_cd?cd_data:(movie_muted?1'b0:movie_data);
 assign output_spdif=select_cd?cd_spdif:movie_spdif;
 assign output_dac_l=select_cd?cd_dac_l:movie_dac_l;
 assign output_dac_r=select_cd?cd_dac_r:movie_dac_r;
endmodule
