// Standalone-file Space-key pause toggle.  Album sessions retain the richer
// media_keyboard_control transport; media_session_control selects which pause
// owner is visible to the shared audio/output state.
module media_pause_control(
 input wire clk,reset,new_session,enabled,osd_open,
 input wire [10:0] key,
 output reg paused=0
);
 reg key_toggle=0;
 reg space_down=0;
 always @(posedge clk) begin
  key_toggle<=key[10];
  if(reset||new_session||!enabled)begin
   paused<=0;
   space_down<=0;
  end else if(key_toggle!=key[10]&&key[8:0]==9'h029)begin
   space_down<=key[9];
   if(key[9]&&!space_down&&!osd_open)paused<=!paused;
  end
 end
endmodule
