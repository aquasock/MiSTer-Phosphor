// Keyboard-only controls for visualizer and aspect selection. State persists
// while the OSD is opened; reset defaults to Waveforms and Standard.
module media_hotkey_options(
 input wire clk,reset,osd_open,input wire [10:0] key,
 output reg [1:0] visualizer=0,output reg widescreen=0
);
 reg key_toggle=0,v_down=0,a_down=0;
 always @(posedge clk)begin
  key_toggle<=key[10];
  if(reset)begin
   visualizer<=0;widescreen<=0;v_down<=0;a_down<=0;
  end else begin
   if(key_toggle!=key[10])begin
    if(key[8:0]==9'h02a)begin
     v_down<=key[9];
     if(key[9]&&!v_down&&!osd_open)visualizer<=visualizer==2?0:visualizer+1'b1;
    end
    if(key[8:0]==9'h01c)begin
     a_down<=key[9];
     if(key[9]&&!a_down&&!osd_open)widescreen<=!widescreen;
    end
   end
  end
 end
endmodule
