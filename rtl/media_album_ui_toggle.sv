// One toggle per physical I-key press. Releases are tracked while the OSD is
// open so menu typing and typematic repeats cannot leak into the player UI.
module media_album_ui_toggle(
 input wire clk,reset,new_file,enabled,osd_open,
 input wire [10:0] key,
 output reg visible=0
);
 reg key_toggle=0;
 reg info_down=0;
 always @(posedge clk) begin
  key_toggle<=key[10];
  // Codec re-sniffing briefly drops `enabled` between entries of the same
  // mixed playlist.  Preserve the user's choice across that capability gap;
  // only a genuinely new mounted file (or core reset) starts with the panel
  // closed.  Key presses remain ignored while the UI is unavailable.
  if(reset||new_file) begin
   visible<=0;
   info_down<=0;
  end else if(key_toggle!=key[10] && key[8:0]==9'h043) begin
   info_down<=key[9];
   if(enabled&&key[9]&&!info_down&&!osd_open) visible<=!visible;
  end
 end
endmodule
