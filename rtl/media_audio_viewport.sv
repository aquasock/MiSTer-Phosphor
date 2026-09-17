// Apply the scaler's inclusive picture bounds to audio graphics only. Geometry
// commits at vertical sync; the physical HDMI raster always remains intact.
module media_audio_viewport(
 input wire clk,enabled,
 input wire [47:0] bounds,
 input wire [23:0] rgb,input wire hs,vs,de,
 output reg [23:0] rgb_out=0,
 output reg hs_out=0,vs_out=0,de_out=0,layout_de=0
);
 reg [47:0] frame_bounds=0;
 reg frame_enabled=0,de_d=0,vs_d=0;
 reg [11:0] x=0,y=0;
 wire inside_x=x>=frame_bounds[47:36]&&x<=frame_bounds[35:24];
 wire inside_y=y>=frame_bounds[23:12]&&y<=frame_bounds[11:0];
 always @(posedge clk)begin
  de_d<=de;vs_d<=vs;
  if(de)x<=x+1'b1;else x<=0;
  if(de_d&&!de)y<=y+1'b1;
  if(vs&&!vs_d)begin
   y<=0;frame_bounds<=bounds;
   frame_enabled<=enabled&&bounds[35:24]>=bounds[47:36]&&bounds[11:0]>=bounds[23:12];
  end
  rgb_out<=rgb;hs_out<=hs;vs_out<=vs;de_out<=de;
  layout_de<=de&&(!frame_enabled||(inside_x&&inside_y));
 end
endmodule
