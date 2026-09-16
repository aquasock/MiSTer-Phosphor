// Stock-Main-compatible control boundary: HPS pass-through, exclusive local
// register transactions, passive HPS-write detection, and rate handoff state.
// Physical HPS busy/timeout behavior still requires board validation.
module media_hdmi_audio_control #(
 parameter integer QUIET_CYCLES=500000,
 parameter integer DRAIN_CYCLES=1,
 parameter integer BUS_FREE_CYCLES=250,
 parameter integer QUARTER_CYCLES=125,
 parameter integer STRETCH_LIMIT=250000,
 parameter integer GRANT_LIMIT=1000000
)(
 input wire clk,reset,want_cd,movie_96k,clients_idle,clock_ready,clock_applied_cd,
 output wire clock_cd,mute,cd_ready,error,
 input wire pad_scl,pad_sda,hps_scl_low,hps_sda_low,
 output wire hps_scl_in,hps_sda_in,drive_scl_low,drive_sda_low
);
 wire hps_changed,config_ready,config_done,config_error,config_request;
 wire[1:0] config_mode;
 wire local_request,local_done,local_grant,local_scl_low,local_sda_low;
 media_audio_rate_control #(.QUIET_CYCLES(QUIET_CYCLES),.DRAIN_CYCLES(DRAIN_CYCLES)) control(
  .clk(clk),.reset(reset),.want_cd(want_cd),.movie_96k(movie_96k),.clients_idle(clients_idle),
  .clock_ready(clock_ready),.clock_applied_cd(clock_applied_cd),.hps_changed(hps_changed),
  .config_ready(config_ready),.config_done(config_done),.config_error(config_error),
  .clock_cd(clock_cd),.mute(mute),.cd_ready(cd_ready),.config_request(config_request),.config_mode(config_mode),.error(error));
 hdmi_i2c_write_watch watch(.clk(clk),.reset(reset),.pad_scl(pad_scl),.pad_sda(pad_sda),.local_grant(local_grant),.changed(hps_changed));
 hdmi_i2c_owner #(.BUS_FREE_CYCLES(BUS_FREE_CYCLES)) owner(
  .clk(clk),.reset(reset),.pad_scl(pad_scl),.pad_sda(pad_sda),.hps_scl_low(hps_scl_low),.hps_sda_low(hps_sda_low),
  .hps_scl_in(hps_scl_in),.hps_sda_in(hps_sda_in),.local_request(local_request),.local_done(local_done),
  .local_grant(local_grant),.local_scl_low(local_scl_low),.local_sda_low(local_sda_low),.drive_scl_low(drive_scl_low),.drive_sda_low(drive_sda_low));
 hdmi_audio_config #(.QUARTER_CYCLES(QUARTER_CYCLES),.STRETCH_LIMIT(STRETCH_LIMIT),.GRANT_LIMIT(GRANT_LIMIT)) config_controller(
  .clk(clk),.reset(reset),.request(config_request),.mode(config_mode),.ready(config_ready),.done(config_done),.error(config_error),
  .local_request(local_request),.local_done(local_done),.local_grant(local_grant),
  .pad_scl(pad_scl),.pad_sda(pad_sda),.local_scl_low(local_scl_low),.local_sda_low(local_sda_low));
endmodule
