// Generic bounded glyph/rectangle scene. Single HDMI clock owns both pages;
// coherent control snapshots arrive upstream through video_config_cdc.
// Producer writes only inactive storage, then commits. Publication/ack occur
// at a frame boundary, so active glyph memory is never changed mid-frame.
module media_overlay_compositor(
 input wire clk,
 input wire [23:0] rgb,input wire hs,vs,de,
 input wire layout_de,
 input wire [15:0] current_epoch,
 input wire text_we,input wire [8:0] text_addr,input wire [7:0] text_data,
 input wire object_we,input wire [3:0] object_addr,input wire [55:0] object_data,
 input wire commit,input wire [15:0] commit_epoch,input wire [1:0] commit_groups,
 input wire [3:0] commit_scale,
 output reg pending=0,output reg acknowledged=0,
 output reg [11:0] width=0,height=0,
 output reg [23:0] rgb_out=0,output reg hs_out=0,vs_out=0,de_out=0
);
// Text: valid[55], group[54], color[53:52], length[29:24], y[23:12], x[11:0].
// Rect: valid[55], group[54], color[53:52], hatch[51], y1[47:36],
// x1[35:24], y0[23:12], x0[11:0]. Bounds are half-open.
(* ramstyle="M10K" *) reg [55:0] staging[0:15];
reg [55:0] active[0:11];
reg [55:0] staging_q;
reg copy_busy=0;
reg [11:0] object_enable=0;
reg staged_matches=0;
reg [3:0] copy_index=0;
wire [3:0] staging_read=copy_busy?copy_index+1'b1:4'd0;
always @(posedge clk) staging_q<=staging[staging_read];
reg [15:0] staged_epoch=0,active_epoch=0;
reg [1:0] staged_groups=0,groups=0;
reg [3:0] staged_scale=4,scale=4;
reg page=0;
(* ramstyle="M10K" *) reg [7:0] text_mem[0:1023];
(* ramstyle="M10K" *) reg [4:0] font[0:2047];
initial $readmemb("rtl/media_overlay_font.mem",font);
integer init_i;
initial begin
 for(init_i=0;init_i<12;init_i=init_i+1) active[init_i]=0;
end
reg [11:0] x=0,y=0;
reg de_d=0,vs_d=0;
wire frame=vs&&!vs_d;
always @(posedge clk) begin
 de_d<=layout_de;vs_d<=vs;staged_matches<=staged_epoch==current_epoch;
 if(layout_de) x<=x+1'b1;else x<=0;
 if(de_d&&!layout_de) begin width<=x;y<=y+1'b1;end
 if(frame) begin height<=y;y<=0;end
 acknowledged<=0;
 if(!pending) begin
  if(text_we) text_mem[{~page,text_addr}]<=text_data;
  if(object_we && object_addr<12) staging[object_addr]<=object_data;
  if(commit) begin
   staged_epoch<=commit_epoch;staged_groups<=commit_groups;
   staged_scale<=commit_scale;pending<=1;
  end
 end
 if(pending && frame && !copy_busy) begin
  copy_busy<=1;copy_index<=0;
 end
 if(copy_busy) begin
  active[copy_index]<=staging_q;
  object_enable[copy_index]<=staging_q[55] && staged_groups[staging_q[54]];
  copy_index<=copy_index+1'b1;
  if(copy_index==11) begin
   copy_busy<=0;pending<=0;acknowledged<=1;
   if(staged_matches) begin
    active_epoch<=staged_epoch;groups<=staged_groups;scale<=staged_scale;page<=~page;
   end else begin groups<=0;object_enable<=0;end
  end
 end
end
// Ten aligned stages: axis comparisons, qualification, object selection,
// offset, coordinate ROM, character RAM, font ROM, palette, blend ROM, output.
// Enable/epoch qualification cannot be folded into the comparison carry path.
(* preserve *) reg [7:0] text_x=0,text_y=0,text_hits=0;
(* preserve *) reg [3:0] rect_x=0,rect_y=0,rect_hits=0;
reg [11:0] x_capture,y_capture,enable_capture;
reg [3:0] scale_capture;
reg page_capture,valid_capture;
(* preserve *) reg epoch_capture=0;
reg [11:0] x0,y0;
reg [3:0] scale0;
reg page0;
integer i;
always @(posedge clk) begin
 x_capture<=x;y_capture<=y;scale_capture<=scale;page_capture<=page;
 enable_capture<=object_enable;valid_capture<=layout_de && !copy_busy;
 epoch_capture<=active_epoch==current_epoch;
 for(integer t=0;t<8;t=t+1) begin
  text_x[t]<=x>=active[t][11:0] && x<active[t][47:36];
  text_y[t]<=y>=active[t][23:12] && y<active[t][35:24];
 end
 for(integer r=8;r<12;r=r+1) begin
  rect_x[r-8]<=x>=active[r][11:0] && x<active[r][35:24];
  rect_y[r-8]<=y>=active[r][23:12] && y<active[r][47:36];
 end
 x0<=x_capture;y0<=y_capture;scale0<=scale_capture;page0<=page_capture;
 text_hits<=text_x & text_y & enable_capture[7:0] & {8{valid_capture && epoch_capture}};
 rect_hits<=rect_x & rect_y & enable_capture[11:8] & {4{valid_capture && epoch_capture}};
end
reg [11:0] selected_x,selected_y;
reg [2:0] selected_slot;
reg [1:0] selected_text,selected_rect;
always @* begin
 i=0;selected_x=0;selected_y=0;selected_slot=0;selected_text=0;selected_rect=0;
 for(i=8;i<12;i=i+1)
  if(rect_hits[i-8]) selected_rect=(active[i][51] && x0[3])?2'd1:active[i][53:52];
 for(i=0;i<8;i=i+1)
  if(text_hits[i]) begin
   selected_x=active[i][11:0];selected_y=active[i][23:12];
   selected_slot=i[2:0];selected_text=active[i][53:52];
  end
end
(* preserve *) reg [11:0] left1,top1,x1,y1;
reg [2:0] slot1;
reg [3:0] scale1;
reg page1,hit1;
reg [1:0] tc1,rc1;
always @(posedge clk) begin
 left1<=selected_x;top1<=selected_y;x1<=x0;y1<=y0;
 slot1<=selected_slot;scale1<=scale0;page1<=page0;hit1<=|text_hits;
 tc1<=selected_text;rc1<=selected_rect;
end
(* preserve *) reg [11:0] dx2,dy2;
reg [2:0] slot2;
reg [3:0] scale2;
reg page2,hit2;
reg [1:0] tc2,rc2;
always @(posedge clk) begin
 dx2<=x1-left1;dy2<=y1-top1;
 slot2<=slot1;scale2<=scale1;page2<=page1;hit2<=hit1;tc2<=tc1;rc2<=rc1;
end
// Integer 1x/2x/3x glyph maps; 3x has 2048 entries for 64-character lines.
(* ramstyle="M10K" *) reg [8:0] coordinates[0:4095];
initial $readmemb("rtl/media_overlay_coordinates.mem",coordinates);
reg [8:0] mapped3;
reg [2:0] slot3,row3;
reg page3,hit3;
reg [1:0] tc3,rc3;
function [2:0] glyph_y;
 input [4:0] d;
 input [3:0] input_scale;
 begin
  if(input_scale==12) case(d)
   0,1,2:glyph_y=0;3,4,5:glyph_y=1;6,7,8:glyph_y=2;
   9,10,11:glyph_y=3;12,13,14:glyph_y=4;15,16,17:glyph_y=5;
   18,19,20:glyph_y=6;default:glyph_y=7;
  endcase
  else if(input_scale==8) glyph_y=d<14?d[3:1]:3'd7;
  else glyph_y=d<7?d[2:0]:3'd7;
 end
endfunction
always @(posedge clk) begin
 mapped3<=coordinates[scale2==12?{1'b1,dx2[10:0]}:{1'b0,(scale2==8),dx2[9:0]}];
 row3<=glyph_y(dy2[4:0],scale2);slot3<=slot2;page3<=page2;
 hit3<=hit2 && dx2<(scale2==12?2048:1024) && dy2<32;tc3<=tc2;rc3<=rc2;
end
reg [7:0] glyph4;
reg [2:0] column4,row4;
reg hit4;
reg [1:0] tc4,rc4;
always @(posedge clk) begin
 glyph4<=text_mem[{page3,slot3,mapped3[8:3]}];
 column4<=mapped3[2:0];row4<=row3;hit4<=hit3 && row3!=7;tc4<=tc3;rc4<=rc3;
end
reg [4:0] bits5;
reg [2:0] column5;
reg hit5;
reg [1:0] tc5,rc5;
always @(posedge clk) begin
 bits5<=font[{glyph4,row4}];column5<=column4;hit5<=hit4;tc5<=tc4;rc5<=rc4;
end
reg [26:0] video_pipe[0:6];
reg [1:0] color6,color7;
reg black_text6=0,black_text7=0;
wire glyph_hit=hit5 && column5<5 && bits5[4-column5];
reg [26:0] video6,video7;
always @(posedge clk) begin
 video_pipe[0]<={hs,vs,de,rgb};
 for(integer v=1;v<7;v=v+1) video_pipe[v]<=video_pipe[v-1];
 video6<=video_pipe[6];
 // Text palette 1 is opaque black only on glyph pixels. Glyph gaps keep
 // the existing rectangle or video beneath them, including subtitle blending.
 black_text6<=glyph_hit && tc5==1;
 color6<=glyph_hit?tc5:rc5;
end
// Exact fixed-palette alpha 160/255, evaluated by byte ROMs. Red and green
// share a dual-read table; no multipliers or divide-by-255 pixel path remains.
(* ramstyle="M10K" *) reg [7:0] blend_rg[0:511];
(* ramstyle="M10K" *) reg [7:0] blend_b[0:255];
initial begin
 $readmemh("rtl/media_overlay_blend_rg.hex",blend_rg);
 $readmemh("rtl/media_overlay_blend_b.hex",blend_b);
end
reg [7:0] dark_r7,dark_g7,dark_b7;
always @(posedge clk) begin
 dark_r7<=blend_rg[{1'b0,video6[23:16]}];
 dark_g7<=blend_rg[{1'b1,video6[15:8]}];
 dark_b7<=blend_b[video6[7:0]];
 video7<=video6;color7<=color6;black_text7<=black_text6;
end
always @(posedge clk) begin
 {hs_out,vs_out,de_out}<=video7[26:24];
 case(color7)
  1:rgb_out<=black_text7?24'h000000:{dark_r7,dark_g7,dark_b7};
  2:rgb_out<=24'h687d89;
  3:rgb_out<=24'heef2f4;
  default:rgb_out<=video7[23:0];
 endcase
end
endmodule
