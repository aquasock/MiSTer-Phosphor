// Stereo XY trace with eight phosphor levels in on-chip RAM. Audio is an
// observation-only tap; line drawing and fading never backpressure playback.
module media_xy_visualizer(
 input wire clk,active,sample_toggle,
 input wire signed [15:0] sample_left,sample_right,
 input wire [23:0] rgb,input wire hs,vs,de,layout_de,
 output reg [23:0] rgb_out=0,output reg hs_out=0,vs_out=0,de_out=0
);
 reg [11:0] x=0,y=0,width=0,height=0;
 reg de_d=0,vs_d=0;
 wire frame_tick=vs&&!vs_d;
 // Geometry settles during blanking; keep min/subtract/add chains out of
 // per-pixel comparisons and phase arithmetic. No video latency is added.
 reg [11:0] side=0,left_edge=0,top_edge=0,right_edge=0,bottom_edge=0;
 always @(posedge clk)begin
  side<=width<height?width:height;
  left_edge<=(width-side)>>1;top_edge<=(height-side)>>1;
  right_edge<=left_edge+side;bottom_edge<=top_edge+side;
 end
 wire in_square=layout_de&&x>=left_edge&&x<right_edge&&y>=top_edge&&y<bottom_edge;
 reg [12:0] phase_x=0,phase_y=0;
 reg [7:0] pixel_x=0,pixel_y=0;
 wire [12:0] next_x=phase_x+13'd256,next_y=phase_y+13'd256;
 always @(posedge clk)begin
  de_d<=layout_de;vs_d<=vs;
  if(layout_de)x<=x+1'b1;else x<=0;
  if(layout_de&&x>=left_edge&&x<right_edge)begin
   if(next_x>={1'b0,side})begin phase_x<=next_x-{1'b0,side};pixel_x<=pixel_x+1'b1;end
   else phase_x<=next_x;
  end else begin phase_x<=0;pixel_x<=0;end
  if(de_d&&!layout_de)begin
   width<=x;y<=y+1'b1;
   if(y>=top_edge&&y<bottom_edge)begin
    if(next_y>={1'b0,side})begin phase_y<=next_y-{1'b0,side};pixel_y<=pixel_y+1'b1;end
    else phase_y<=next_y;
   end
  end
  if(frame_tick)begin height<=y;y<=0;phase_y<=0;pixel_y<=0;end
 end

 // Separate one-bit planes permit 8192x1 M10K packing: 24 blocks total.
 (* ramstyle="M10K, no_rw_check" *) reg phosphor0[0:65535];
 (* ramstyle="M10K, no_rw_check" *) reg phosphor1[0:65535];
 (* ramstyle="M10K, no_rw_check" *) reg phosphor2[0:65535];
 reg clear=1;reg [15:0] clear_address=0,fade_address=0;
 reg fade_busy=0;reg [1:0] fade_state=0;
 reg seen_toggle=0,pending=0,have_previous=0,drawing=0;
 reg [7:0] pending_x=128,pending_y=128,previous_x=128,previous_y=128;
 reg [7:0] draw_x=64,draw_y=64,end_x=64,end_y=64,dx=0,dy=0;
 reg step_x=0,step_y=0;
 reg signed [9:0] error=0;
 wire signed [10:0] twice_error=$signed({error[9],error})<<<1;
 wire move_x=twice_error>-$signed({3'd0,dy});
 wire move_y=twice_error<$signed({3'd0,dx});
 wire [15:0] ram_address=clear?clear_address:drawing?{draw_y,draw_x}:fade_address;
 reg [2:0] fade_q=0,display_q=0;
 // Keep a fabric register after the banked RAM read mux, using the
 // existing three-cycle fade transaction to avoid a RAM-to-RAM critical path.
 (* preserve *) reg [2:0] fade_pixels=0;
 wire [2:0] faded=fade_pixels==0?3'd0:fade_pixels-3'd1;
 wire ram_write=clear||drawing||(fade_busy&&fade_state==2);
 wire [2:0] ram_data=clear?3'd0:drawing?3'd7:faded;
 always @(posedge clk)begin
  fade_pixels<=fade_q;
  fade_q<={phosphor2[ram_address],phosphor1[ram_address],phosphor0[ram_address]};
  if(ram_write)begin
   phosphor0[ram_address]<=ram_data[0];
   phosphor1[ram_address]<=ram_data[1];
   phosphor2[ram_address]<=ram_data[2];
  end
  display_q<={phosphor2[{pixel_y,pixel_x}],phosphor1[{pixel_y,pixel_x}],phosphor0[{pixel_y,pixel_x}]};
 end
 always @(posedge clk)begin
  seen_toggle<=sample_toggle;
  if(!active)begin
   clear<=1;clear_address<=0;pending<=0;drawing<=0;have_previous<=0;fade_busy<=0;fade_state<=0;
  end else if(clear)begin
   clear_address<=clear_address+1'b1;
   if(&clear_address)clear<=0;
  end else begin
   // The latest sample wins if display work momentarily falls behind.
   if(sample_toggle!=seen_toggle)begin
    pending_x<=sample_left[15:8]^8'h80;pending_y<=~(sample_right[15:8]^8'h80);pending<=1;
   end
   if(frame_tick&&!fade_busy)begin fade_address<=0;fade_busy<=1;fade_state<=0;end
   if(drawing)begin
    fade_state<=0;
    if(draw_x==end_x&&draw_y==end_y)drawing<=0;
    else begin
     if(move_x)draw_x<=step_x?draw_x+1'b1:draw_x-1'b1;
     if(move_y)draw_y<=step_y?draw_y+1'b1:draw_y-1'b1;
     error<=error-(move_x?$signed({2'd0,dy}):10'sd0)+(move_y?$signed({2'd0,dx}):10'sd0);
    end
   end else if(pending)begin
    pending<=sample_toggle!=seen_toggle;drawing<=1;fade_state<=0;
    draw_x<=have_previous?previous_x:pending_x;draw_y<=have_previous?previous_y:pending_y;
    end_x<=pending_x;end_y<=pending_y;
    dx<=!have_previous?8'd0:(pending_x>=previous_x?pending_x-previous_x:previous_x-pending_x);
    dy<=!have_previous?8'd0:(pending_y>=previous_y?pending_y-previous_y:previous_y-pending_y);
    error<=!have_previous?10'sd0:
     $signed({2'd0,(pending_x>=previous_x?pending_x-previous_x:previous_x-pending_x)})-
     $signed({2'd0,(pending_y>=previous_y?pending_y-previous_y:previous_y-pending_y)});
    step_x<=pending_x>=previous_x;step_y<=pending_y>=previous_y;
    previous_x<=pending_x;previous_y<=pending_y;have_previous<=1;
   end else if(fade_busy)begin
    if(fade_state==2)begin fade_state<=0;fade_address<=fade_address+1'b1;if(&fade_address)fade_busy<=0;end
    else fade_state<=fade_state+1'b1;
   end
  end
 end

 (* altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) reg [26:0] video[0:7];
 (* altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) reg [7:0] enable_pipe=0;
 (* altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) reg [2:0] intensity[0:6];
 reg square_q=0;
 always @(posedge clk)begin
  video[0]<={hs,vs,de,rgb};for(integer k=1;k<8;k=k+1)video[k]<=video[k-1];
  enable_pipe<={enable_pipe[6:0],active&&layout_de&&side>=256};
  square_q<=in_square&&!clear;
  intensity[0]<=square_q?display_q:3'd0;
  for(integer k=1;k<7;k=k+1)intensity[k]<=intensity[k-1];
  {hs_out,vs_out,de_out}<=video[7][26:24];
  rgb_out<=enable_pipe[7]?{2'b00,intensity[6],intensity[6],intensity[6],intensity[6],intensity[6][2:1],2'b00,intensity[6],intensity[6]}:video[7][23:0];
 end
endmodule
