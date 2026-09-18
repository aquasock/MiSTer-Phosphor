// Native-raster port of Phosphor's historical standalone-audio layout.
// MP3A metadata and RGB332 artwork are supplied by the builder-generated FLAC.
// The renderer is placed on the native raster before the HDMI/analog split.
(* altera_attribute="-name AUTO_DSP_RECOGNITION OFF" *)
module media_flac_album_ui(
 input wire clk,enabled,
 input wire metadata_valid,artwork_valid,current_title_long,input wire [6:0] track_count,current_track,
 output reg [13:0] metadata_address=0,input wire [7:0] metadata_data,
 input wire [23:0] rgb,input wire hs,vs,de,layout_de,
 output reg [23:0] rgb_out=0,output reg hs_out=0,vs_out=0,de_out=0
);
 reg [11:0] x=0,y=0;
 reg de_d=0,vs_d=0;
 always @(posedge clk) begin
  de_d<=layout_de;vs_d<=vs;
  if(layout_de)x<=x+1'b1;else x<=0;
  if(de_d&&!layout_de)y<=y+1'b1;
 if(vs&&!vs_d)y<=0;
 end

 // The historical panel group is 328 lines tall. Offset its local coordinate
 // by 76 lines so the complete group is vertically centered in 480 lines.
 wire [11:0] ui_y;
 assign ui_y = (y >= 12'd76) ? (y - 12'd76) : 12'hfff;
 wire art_panel=x>=12'd28&&x<12'd228&&ui_y>=12'd0&&ui_y<12'd200;
 wire art_inner=x>=12'd36&&x<12'd220&&ui_y>=12'd8&&ui_y<12'd192;
 wire info_panel=x>=12'd28&&x<12'd228&&ui_y>=12'd212&&ui_y<12'd328;
 wire list_panel=x>=12'd242&&x<12'd612&&ui_y>=12'd0&&ui_y<12'd328;
 reg [6:0] display_start;
 always @* begin
  if(current_track<=3||track_count<=6)display_start=1;
  else if(current_track+3>track_count)display_start=track_count-5;
  else display_start=current_track-2;
 end
 wire [2:0] selected_slot=current_track>=display_start?current_track-display_start:0;
 wire selected_row=x>=12'd250&&x<12'd604&&current_track>=display_start&&selected_slot<6&&
  ui_y>=12'd52+selected_slot*42&&ui_y<12'd86+selected_slot*42;
 wire separator=x>=12'd256&&x<12'd598&&
   ((ui_y>=12'd84&&ui_y<12'd85&&track_count>=display_start)||
    (ui_y>=12'd126&&ui_y<12'd127&&track_count>=display_start+1'b1)||
    (ui_y>=12'd168&&ui_y<12'd169&&track_count>=display_start+2'd2)||
    (ui_y>=12'd210&&ui_y<12'd211&&track_count>=display_start+2'd3)||
    (ui_y>=12'd252&&ui_y<12'd253&&track_count>=display_start+3'd4)||
    (ui_y>=12'd294&&ui_y<12'd295&&track_count>=display_start+3'd5));
 wire art_border=art_panel&&!art_inner;
 wire info_border=info_panel&&(x<12'd30||x>=12'd226||ui_y<12'd214||ui_y>=12'd326);
 wire list_border=list_panel&&(x<12'd244||x>=12'd610||ui_y<12'd2||ui_y>=12'd326);

 reg [3:0] text_line;
 reg [11:0] text_x,text_y;
 reg [5:0] text_length;
 reg [1:0] text_color;
 always @* begin
  text_line=15;text_x=0;text_y=0;text_length=0;text_color=2;
  if(ui_y>=226&&ui_y<242&&x>=40&&x<220)begin text_line=2;text_x=40;text_y=226;text_length=metadata_valid?15:3;text_color=3;end
  else if(ui_y>=256&&ui_y<272&&x>=40&&x<220)begin text_line=3;text_x=40;text_y=256;text_length=metadata_valid?15:3;text_color=3;end
  else if(ui_y>=286&&ui_y<302&&x>=40&&x<220)begin text_line=4;text_x=40;text_y=286;text_length=metadata_valid?15:3;text_color=3;end
  else if(ui_y>=16&&ui_y<32&&x>=258&&x<470)begin text_line=5;text_x=258;text_y=16;text_length=16;text_color=3;end
  else if(ui_y>=64&&ui_y<80&&x>=260&&x<590)begin text_line=6;text_x=260;text_y=64;text_length=metadata_valid ? 27:14;text_color=(current_track==display_start) ? 3:2;end
  else if(ui_y>=106&&ui_y<122&&x>=260&&x<590)begin text_line=7;text_x=260;text_y=106;text_length=metadata_valid ? 27:14;text_color=(current_track==display_start+1'b1) ? 3:2;end
  else if(ui_y>=148&&ui_y<164&&x>=260&&x<590)begin text_line=8;text_x=260;text_y=148;text_length=metadata_valid ? 27:14;text_color=(current_track==display_start+2'd2) ? 3:2;end
  else if(ui_y>=190&&ui_y<206&&x>=260&&x<590)begin text_line=9;text_x=260;text_y=190;text_length=metadata_valid ? 27:14;text_color=(current_track==display_start+2'd3) ? 3:2;end
  else if(ui_y>=232&&ui_y<248&&x>=260&&x<590)begin text_line=10;text_x=260;text_y=232;text_length=metadata_valid ? 27:14;text_color=(current_track==display_start+3'd4) ? 3:2;end
  else if(ui_y>=274&&ui_y<290&&x>=260&&x<590)begin text_line=11;text_x=260;text_y=274;text_length=metadata_valid ? 27:14;text_color=(current_track==display_start+3'd5) ? 3:2;end
 end

 reg [255:0] line_text;
 always @* begin
  case(text_line)
   0:line_text="";
   1:line_text="";
   2:line_text="---";
   3:line_text="---";
   4:line_text="---";
   5:line_text="CURRENT PLAYLIST";
   6:line_text="01  TRACK TITLE";
   7:line_text="02  TRACK TITLE";
   8:line_text="03  TRACK TITLE";
   9:line_text="04  TRACK TITLE";
   10:line_text="05  TRACK TITLE";
   11:line_text="06  TRACK TITLE";
   default:line_text=0;
  endcase
 end
 wire [11:0] text_dx=x-text_x;
 reg [5:0] char_index;
 always @* begin
  if(text_dx<12)char_index=0;
  else if(text_dx<24)char_index=1;
  else if(text_dx<36)char_index=2;
  else if(text_dx<48)char_index=3;
  else if(text_dx<60)char_index=4;
  else if(text_dx<72)char_index=5;
  else if(text_dx<84)char_index=6;
  else if(text_dx<96)char_index=7;
  else if(text_dx<108)char_index=8;
  else if(text_dx<120)char_index=9;
  else if(text_dx<132)char_index=10;
  else if(text_dx<144)char_index=11;
  else if(text_dx<156)char_index=12;
  else if(text_dx<168)char_index=13;
  else if(text_dx<180)char_index=14;
  else if(text_dx<192)char_index=15;
  else if(text_dx<204)char_index=16;
  else if(text_dx<216)char_index=17;
  else if(text_dx<228)char_index=18;
  else if(text_dx<240)char_index=19;
  else if(text_dx<252)char_index=20;
  else if(text_dx<264)char_index=21;
  else if(text_dx<276)char_index=22;
  else if(text_dx<288)char_index=23;
  else if(text_dx<300)char_index=24;
  else if(text_dx<312)char_index=25;
  else char_index=26;
 end
 wire text_candidate=text_line!=15&&x>=text_x&&char_index<text_length;
 wire [3:0] glyph_x=(text_dx-char_index*12)>>1;
 wire [2:0] glyph_y=(ui_y-text_y)>>1;
 reg [7:0] static_glyph;
 reg dynamic_glyph;
 reg [13:0] text_metadata_address;
 reg [6:0] row_track;
 reg [3:0] row_tens;
 wire [6:0] row_ones=row_track-(row_tens<<3)-(row_tens<<1);
 always @* begin
  static_glyph=0;dynamic_glyph=0;text_metadata_address=0;row_track=0;row_tens=0;
  // String literals occupy the least-significant bytes of line_text, with
  // their first character at byte text_length-1.
  if(text_candidate)static_glyph=line_text[((text_length-char_index)*8)-1 -: 8];
  if(metadata_valid&&text_candidate)begin
   if(text_line==2)begin
    if(current_title_long&&char_index>=12)static_glyph=".";
    else begin dynamic_glyph=1;text_metadata_address=14'd72+((current_track?current_track:1)-1'b1)*32+char_index;end
   end else if(text_line==3)begin
    dynamic_glyph=1;text_metadata_address=14'd40+char_index;
   end else if(text_line==4)begin
    dynamic_glyph=1;text_metadata_address=14'd8+char_index;
   end else if(text_line>=6&&text_line<=11)begin
    row_track=display_start+(text_line-6);
    if(row_track>=90)row_tens=9;else if(row_track>=80)row_tens=8;
    else if(row_track>=70)row_tens=7;else if(row_track>=60)row_tens=6;
    else if(row_track>=50)row_tens=5;else if(row_track>=40)row_tens=4;
    else if(row_track>=30)row_tens=3;else if(row_track>=20)row_tens=2;
    else if(row_track>=10)row_tens=1;
    if(row_track>track_count)static_glyph=" ";
    else if(char_index==0)static_glyph=8'd48+row_tens;
    else if(char_index==1)static_glyph=8'd48+row_ones;
    else if(char_index==2)static_glyph=" ";
    else begin dynamic_glyph=1;text_metadata_address=14'd72+(row_track-1'b1)*32+(char_index-3);end
   end
  end
 end

 wire art_request=enabled&&metadata_valid&&artwork_valid&&art_inner;
 wire [6:0] art_x=(x-12'd36)>>1;
 wire [6:0] art_y=(ui_y-12'd8)>>1;
 (* multstyle="logic" *) wire [13:0] art_row_offset=art_y*92;
 always @* metadata_address=art_request?14'd3240+art_row_offset+art_x:text_metadata_address;

 (* ramstyle="M10K" *) reg [4:0] font[0:2047];
 initial $readmemb("rtl/media_overlay_font.mem",font);
 reg [4:0] font_bits=0;
 reg [3:0] glyph_x_q=0,glyph_x_qq=0;
 reg [2:0] glyph_y_q=0;
 reg [7:0] static_glyph_q=0;
 reg [1:0] text_color_q=0,text_color_qq=0;
 reg text_candidate_q=0,text_candidate_qq=0,dynamic_glyph_q=0;
 reg art_request_q=0,art_request_qq=0,enabled_q=0,enabled_qq=0;
 reg [26:0] video_q=0,video_qq=0;
 reg [23:0] base_color=0,base_color_q=0,art_color_q=0;
 always @(posedge clk) begin
  video_q<={hs,vs,de,rgb};
  enabled_q<=enabled;
  glyph_x_q<=glyph_x;glyph_y_q<=glyph_y;text_color_q<=text_color;text_candidate_q<=text_candidate;
  dynamic_glyph_q<=dynamic_glyph;static_glyph_q<=static_glyph;art_request_q<=art_request;
  if(!enabled) base_color<=rgb;
  else if(art_inner) base_color<=24'h0b1018;
  else if(selected_row) base_color<={2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]}+24'h182028;
  else if(art_panel||info_panel||list_panel) base_color<={2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]}+24'h080c12;
  else base_color<=rgb;
  if(enabled&&(art_border||info_border||list_border))base_color<=24'h607786;
  if(enabled&&separator)base_color<=24'h263640;
  video_qq<=video_q;base_color_q<=base_color;
  glyph_x_qq<=glyph_x_q;text_color_qq<=text_color_q;text_candidate_qq<=text_candidate_q;
  art_request_qq<=art_request_q;enabled_qq<=enabled_q;
  font_bits<=font[{dynamic_glyph_q?metadata_data:static_glyph_q,glyph_y_q}];
  art_color_q<={{metadata_data[7:5],metadata_data[7:5],metadata_data[7:6]},
                 {metadata_data[4:2],metadata_data[4:2],metadata_data[4:3]},
                 {metadata_data[1:0],metadata_data[1:0],metadata_data[1:0],metadata_data[1:0]}};
 end
 wire glyph_hit=text_candidate_qq&&glyph_x_qq<5&&font_bits[4-glyph_x_qq];
 always @(posedge clk) begin
  {hs_out,vs_out,de_out}<=video_qq[26:24];
  rgb_out<=art_request_qq?art_color_q:base_color_q;
  if(enabled_qq&&glyph_hit)rgb_out<=text_color_qq==3?24'heef2f4:24'h70808a;
 end
endmodule
