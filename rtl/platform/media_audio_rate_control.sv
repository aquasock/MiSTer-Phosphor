// Transactional movie/CD output handoff in the platform control-clock domain.
// mute must pause/drain the PCM consumer; clients_idle acknowledges that drain.
// clock_ready acknowledges the selected clock and serializer settling. Neither
// acknowledgement may be replaced by an unsynchronized combinational signal.
module media_audio_rate_control #(
 parameter integer QUIET_CYCLES=500000,
 parameter integer DRAIN_CYCLES=1
)(
 input wire clk,reset,want_cd,movie_96k,
 input wire clients_idle,clock_ready,clock_applied_cd,hps_changed,
 input wire config_ready,config_done,config_error,
 output reg clock_cd,
 output wire mute,cd_ready,config_request,
 output reg[1:0] config_mode,
 output reg error
);
 localparam RUN=0,DRAIN=1,SELECT=2,QUIET=3,ISSUE=4,WAIT=5,FAILED=6;
 localparam QW=$clog2(QUIET_CYCLES+1);
 reg[2:0] state;
 localparam DW=$clog2(DRAIN_CYCLES+1);
 reg[DW-1:0] drain_count=0;
 reg dirty;reg[QW-1:0] quiet_count;
 wire[1:0] wanted_mode=want_cd?2'd1:movie_96k?2'd2:2'd0;
 assign mute=state!=RUN||want_cd!=clock_cd||(want_cd&&(hps_changed||!clock_ready||clock_applied_cd!=clock_cd));
 assign cd_ready=want_cd&&clock_cd&&!mute&&!error;
 assign config_request=state==ISSUE;
 always @(posedge clk)begin
  if(reset)begin state<=RUN;clock_cd<=0;config_mode<=0;error<=0;dirty<=0;quiet_count<=0;drain_count<=0;end
  else begin
   if(state!=DRAIN)drain_count<=0;else if(drain_count!=DW'(DRAIN_CYCLES-1))drain_count<=drain_count+1'b1;
   if(hps_changed)begin dirty<=1;quiet_count<=0;end
   case(state)
    RUN:if(want_cd!=clock_cd||(want_cd&&(hps_changed||!clock_ready||clock_applied_cd!=clock_cd)))begin state<=DRAIN;error<=0;end
    DRAIN:if(clients_idle&&drain_count==DW'(DRAIN_CYCLES-1))begin clock_cd<=want_cd;config_mode<=wanted_mode;state<=SELECT;end
    SELECT:if(clock_ready&&clock_applied_cd==clock_cd)begin state<=QUIET;quiet_count<=0;end
    QUIET:if(wanted_mode!=config_mode)state<=DRAIN;
     else if(!hps_changed)begin
      if(quiet_count==QW'(QUIET_CYCLES-1))begin state<=ISSUE;dirty<=0;end
      else quiet_count<=quiet_count+1'b1;
     end
    ISSUE:if(config_ready)state<=WAIT;
    WAIT:if(config_done)begin
     if(config_error)begin state<=FAILED;error<=1;end
     else if(dirty||hps_changed||wanted_mode!=config_mode)state<=DRAIN;
     else state<=RUN;
    end
    FAILED:if(wanted_mode!=config_mode||hps_changed)begin state<=DRAIN;error<=0;end
    default:state<=FAILED;
   endcase
  end
 end
endmodule
