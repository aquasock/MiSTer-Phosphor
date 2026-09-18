// One toggle per physical M-key press. Releases are tracked while the OSD is
// open so menu typing and typematic repeats cannot leak into the player UI.
module media_album_ui_toggle(
 input wire clk,reset,new_file,enabled,osd_open,
 input wire [10:0] key,
 output reg visible=0
);
 reg key_toggle=0;
 reg m_down=0;
 always @(posedge clk) begin
  key_toggle<=key[10];
  if(reset||new_file||!enabled) begin
   visible<=0;
   m_down<=0;
  end else if(key_toggle!=key[10] && key[8:0]==9'h03a) begin
   m_down<=key[9];
   if(key[9]&&!m_down&&!osd_open) visible<=!visible;
  end
 end
endmodule
