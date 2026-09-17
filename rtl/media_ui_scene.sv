// Scene assembler. Only this producer writes the compositor's inactive page.
// Subtitle content uses the retained auxiliary provider (slots 4-7).
// Slot 3 is disabled; playback status labels are no longer generated.
module media_ui_scene(
 input wire clk,ce,input wire [90:0] state_in,input wire [11:0] width,height,
 input wire pending,acknowledged,
 output reg text_we=0,output reg [8:0] text_addr=0,output reg [7:0] text_data=0,
 output reg object_we=0,output reg [3:0] object_addr=0,output reg [55:0] object_data=0,
 output reg commit=0,output reg [15:0] commit_epoch=0,
 output reg [1:0] commit_groups=0,output reg [3:0] commit_scale=4,
 input wire aux_text_we,input wire [7:0] aux_text_addr,aux_text_data,
 input wire aux_object_we,input wire [1:0] aux_object_addr,input wire [55:0] aux_object_data,
 input wire aux_commit,input wire [15:0] aux_epoch,input wire aux_visible,
 input wire aux_auto_layout,input wire [6:0] aux_length0,aux_length1
);
(* ramstyle="M10K" *) reg [7:0] auxiliary_text[0:255];
reg [55:0] auxiliary_objects[0:3];
reg [15:0] auxiliary_epoch=0;
reg auxiliary_visible=0,auxiliary_editing=0;
reg [15:0] auxiliary_revision=0,revision=0;
reg [7:0] aux_read;
reg ack_pending=0;
reg [90:0] snapshot=0;
reg [11:0] w=0,h=0;
reg [3:0] scale=4;
reg [7:0] state=0,resume_state=0;
reg [2:0] field=0;
reg [5:0] ch=0;
reg [6:0] hours=0,minutes=0,seconds=0;
reg [11:0] tx=0,ty=0,tw=0,th=0,track_x0=0,track_x1=0,fill_x0=0,fill_x1=0;
reg [11:0] subtitle_bottom=0,bar_height=0,time_y=0;
wire [11:0] font_height=scale==12?12'd21:scale==8?12'd14:12'd7;
wire [11:0] bar_inset=scale==12?12'd6:scale==8?12'd4:12'd2;
reg [11:0] track_y0=0,track_y1=0,fill_y0=0,fill_y1=0;
reg [55:0] subtitle_rect0=0,subtitle_rect1=0;
reg [11:0] fraction=0;
reg [47:0] product=0,multiplicand=0;
reg [11:0] multiplier=0;
reg [3:0] multiply_count=0;
reg [7:0] multiply_resume=0;
reg [24:0] product_low=0;
reg [35:0] remaining_delta=0,time_rounded=0;
reg [34:0] remaining=0,clamped_position=0,time_operand=0;
reg [11:0] glyph_span=0;
reg [12:0] text_span=0;
reg div_start=0;
reg [47:0] numerator=0;
reg [34:0] denominator=1;
wire div_busy,div_done;
wire [47:0] quotient;
wire [34:0] remainder;
media_ui_divider divider(.clk(clk),.ce(ce),.start(div_start),.numerator(numerator),.denominator(denominator),
 .busy(div_busy),.done(div_done),.quotient(quotient),.remainder(remainder));
task divide;
 input [47:0] n;input [34:0] d;input [7:0] next_state;
 begin numerator<=n;denominator<=d;div_start<=1;resume_state<=next_state;state<=250;end
endtask
task multiply;
 input [47:0] n;input [11:0] factor;input [7:0] next_state;
 begin
  product<=0;multiplicand<=n;multiplier<=factor;multiply_count<=12;
  multiply_resume<=next_state;state<=36;
 end
endtask
reg [23:0] time_digits=0;
wire known=snapshot[70];
wire [34:0] duration=snapshot[69:35],position=snapshot[34:0];

// Three black clocks share the bar. Slot 3 stays disabled for object stability.
wire [6:0] length=field<3?7'd8:field==4?aux_length0:field==5?aux_length1:7'd0;
function [7:0] time_glyph;
 input [5:0] index;
 begin
  if(index==2 || index==5) time_glyph=":";
  else if(field!=0 && !known) time_glyph="-";
  else case(index)
   0:time_glyph={4'h3,time_digits[23:20]};1:time_glyph={4'h3,time_digits[19:16]};
   3:time_glyph={4'h3,time_digits[15:12]};4:time_glyph={4'h3,time_digits[11:8]};
   6:time_glyph={4'h3,time_digits[7:4]};default:time_glyph={4'h3,time_digits[3:0]};
  endcase
 end
endfunction
integer ai;
initial for(ai=0;ai<4;ai=ai+1) auxiliary_objects[ai]=0;
always @(posedge clk) begin
 if(ce && state==35 && (acknowledged || ack_pending)) ack_pending<=0;
 else if(acknowledged) ack_pending<=1;
 if(aux_text_we || aux_object_we) auxiliary_editing<=1;
 if(aux_commit) auxiliary_editing<=0;
 if(aux_text_we) auxiliary_text[aux_text_addr]<=aux_text_data;
 if(aux_object_we) auxiliary_objects[aux_object_addr]<=aux_object_data;
 if(aux_commit) begin auxiliary_epoch<=aux_epoch;auxiliary_visible<=aux_visible;end
 // A provider change during assembly cancels publication; the next complete
 // scene copies its retained content. Producers finish writes before commit.
 if(aux_text_we || aux_object_we || aux_commit) auxiliary_revision<=auxiliary_revision+1'b1;
 aux_read<=auxiliary_text[{field[1:0],ch}];
 if(ce) begin
 remaining_delta<={1'b0,duration}-{1'b0,position};
 remaining<=remaining_delta[35]?35'd0:remaining_delta[34:0];
 clamped_position<=remaining_delta[35]?duration:position;
 glyph_span<=({5'd0,length}<<2)+({5'd0,length}<<1);
 text_span<=scale==12 ? ({1'b0,glyph_span}<<3)+({1'b0,glyph_span}<<2) : scale==8 ? {1'b0,glyph_span}<<3 : {1'b0,glyph_span}<<2;
 text_we<=0;object_we<=0;commit<=0;div_start<=0;
 case(state)
  0:if(!pending && !auxiliary_editing && width!=0 && height!=0) begin
   snapshot<=state_in;w<=width;h<=height;revision<=auxiliary_revision;
   scale<=height>=1000?12:height>=700?8:4;field<=0;state<=70;
  end
  // Center a taller bar in the reserved gap below the lower subtitle line.
  // Reserve that same area even when no subtitle is currently visible.
  70:multiply({36'd0,h},12'd445,71);
  71:divide(product,35'd480,72);
  72:begin subtitle_bottom<=quotient[11:0]+font_height+12'd2;multiply({36'd0,h},12'd18,73);end
  73:divide(product,35'd480,74);
  74:begin bar_height<=quotient[11:0];state<=75;end
  75:begin track_y0<=subtitle_bottom+((h-subtitle_bottom-bar_height)>>1);state<=76;end
  76:begin
   track_y1<=track_y0+bar_height;time_y<=track_y0+((bar_height-font_height)>>1);
   fill_y0<=track_y0+bar_inset;fill_y1<=track_y0+bar_height-bar_inset;state<=1;
  end
  1:begin
   if(field<3) begin time_operand<=field==0?position:field==1?duration:remaining;state<=40;end
   else begin ch<=0;state<=5;end
  end
  40:begin time_rounded<={1'b0,time_operand}+(field==0?36'd0:36'd359999);state<=41;end
  41:divide({12'd0,time_rounded},35'd360000,2);
  2:divide(quotient>359999?48'd359999:quotient,35'd3600,3);
  3:begin hours<=quotient[6:0];divide({13'd0,remainder},35'd60,4);end
  4:begin minutes<=quotient[6:0];seconds<=remainder[6:0];ch<=0;state<=60;end
  // Convert decimal digits once per field on the existing sequential unit.
  // This avoids inferred combinational /10 and %10 networks in glyph writes.
  60:divide({41'd0,hours},35'd10,61);
  61:begin
   time_digits[23:20]<=quotient[3:0];time_digits[19:16]<=remainder[3:0];
   divide({41'd0,minutes},35'd10,62);
  end
  62:begin
   time_digits[15:12]<=quotient[3:0];time_digits[11:8]<=remainder[3:0];
   divide({41'd0,seconds},35'd10,63);
  end
  63:begin time_digits[7:4]<=quotient[3:0];time_digits[3:0]<=remainder[3:0];state<=5;end
  5:begin
   text_we<=1;text_addr<={field,ch};
   if({1'b0,ch}>=length) text_data<=0;
   else text_data<=time_glyph(ch);
   if(ch==63) state<=6;else ch<=ch+1'b1;
  end
  6:multiply({36'd0,w},field==0?12'd141:field==2?12'd579:12'd360,46);
  46:divide(product,35'd720,7);
  7:begin
   tw<=12'((text_span+13'd3)>>2);th<=font_height;
   tx<=quotient[11:0]-12'(text_span>>3);
   if(field<3)begin ty<=time_y;state<=9;end
   else multiply({36'd0,h},field==4?(aux_length1!=0?12'd431:12'd445):12'd445,47);
  end
  47:divide(product,35'd480,8);
  8:begin ty<=quotient[11:0];state<=9;end
  9:begin
   object_we<=1;object_addr<={1'b0,field};
   object_data<={length!=0,(field>=4),(field<3?2'd1:2'd3),4'd0,(tx+tw),(ty+th),ty,tx};
   if(field==4)subtitle_rect0<={length!=0,1'b1,2'd1,4'd0,(ty+th+12'd2),(tx+tw+12'd2),(ty-12'd2),(tx-12'd2)};
   if(field==5)subtitle_rect1<={length!=0,1'b1,2'd1,4'd0,(ty+th+12'd2),(tx+tw+12'd2),(ty-12'd2),(tx-12'd2)};
   if(field>=4) begin field<=field+1'b1;ch<=0;state<=10;end
   else if(field==2) state<=13;
   else begin field<=field+1'b1;state<=1;end
  end
  13:begin // Explicitly disable the unused former status object on each page.
   object_we<=1;object_addr<=3;object_data<=0;field<=4;ch<=0;state<=10;
  end
  10:state<=11; // synchronous retained-provider character read
  11:begin
   text_we<=1;text_addr<={field,ch};text_data<=aux_read;
   if(ch==63) state<=12;else begin ch<=ch+1'b1;state<=10;end
  end
  12:if(aux_auto_layout && field<6) state<=6;else begin
   object_we<=1;object_addr<={1'b0,field};object_data<=auxiliary_objects[field[1:0]];
   if(field==7) state<=20;else begin field<=field+1'b1;ch<=0;state<=10;end
  end
  20:multiply({36'd0,w},12'd32,50);
  50:divide(product,35'd720,21);
  21:begin track_x0<=quotient[11:0];multiply({36'd0,w},12'd688,51);end
  51:divide(product,35'd720,22);
  22:begin track_x1<=quotient[11:0];multiply({36'd0,w},12'd34,52);end
  52:divide(product,35'd720,23);
  23:begin fill_x0<=quotient[11:0];multiply({36'd0,w},12'd686,53);end
  53:divide(product,35'd720,24);
  24:begin fill_x1<=quotient[11:0];state<=28;end
  28:begin
   if(known && duration!=0) multiply({13'd0,clamped_position},fill_x1-fill_x0,37);
   else begin fraction<=fill_x1-fill_x0;state<=30;end
  end
  36:begin
   product_low<={1'b0,product[23:0]}+{1'b0,(multiplier[0]?multiplicand[23:0]:24'd0)};
   state<=42;
  end
  42:begin
   product[23:0]<=product_low[23:0];
   product[47:24]<=product[47:24]+(multiplier[0]?multiplicand[47:24]:24'd0)+{23'd0,product_low[24]};
   multiplicand<=multiplicand<<1;multiplier<=multiplier>>1;
   multiply_count<=multiply_count-1'b1;
   if(multiply_count==1) state<=multiply_resume;else state<=36;
  end
  37:divide(product,duration,29);
  29:begin fraction<=quotient[11:0];state<=30;end
  30:begin object_we<=1;object_addr<=8;
   object_data<={1'b1,1'b0,2'd2,4'd0,track_y1,track_x1,track_y0,track_x0};state<=31;end
  31:begin object_we<=1;object_addr<=9;
   object_data<={1'b1,1'b0,(known?2'd3:2'd2),!known,3'd0,fill_y1,(fill_x0+fraction),fill_y0,fill_x0};state<=32;end
  32:begin object_we<=1;object_addr<=10;object_data<=aux_auto_layout?subtitle_rect0:56'd0;state<=33;end
  33:begin object_we<=1;object_addr<=11;object_data<=aux_auto_layout?subtitle_rect1:56'd0;state<=34;end
  34:begin
   if(snapshot[90:75]==state_in[90:75] && revision==auxiliary_revision) begin
    commit<=1;commit_epoch<=snapshot[90:75];commit_scale<=scale;
    commit_groups<={auxiliary_visible && auxiliary_epoch==snapshot[90:75],snapshot[73]};state<=35;
   end else state<=0;
  end
  35:if(acknowledged || ack_pending) state<=0;
  250:if(div_done) state<=resume_state;
  default:state<=0;
 endcase
 end
end
endmodule
