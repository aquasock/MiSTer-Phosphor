// Parses the portable subset of an external CUE sheet needed for a single
// continuous FLAC image. Leading whitespace is accepted; each INDEX 01
// timestamp is published in native CUE frames (75 per second). Album control
// converts those frames to samples after the FLAC STREAMINFO rate is known.
module media_cue_index(
 input wire clk,reset,enable,byte_valid,input wire[7:0] byte_data,input wire byte_eof,
 output reg track_write=0,output reg[6:0] track_address=0,
 output reg[31:0] track_frame=0,output reg[6:0] track_count=0,
 output reg ready=0,done=0,error=0
);
 localparam LINE=0,I=1,N=2,D=3,E=4,X=5,WS_INDEX=6,NUM0=7,NUM1=8,
            WS_TIME=9,MINUTES=10,SECONDS=11,FRAMES=12,IGNORE=13;
 reg[3:0] state=LINE;reg[31:0] minutes=0;reg[6:0] seconds=0,frames=0;
 reg[3:0] digits=0;reg index01=0;reg[31:0] last_frame=0;
 wire newline=byte_data==8'h0a||byte_data==8'h0d;
 wire whitespace=byte_data==8'h20||byte_data==8'h09;
 wire digit=byte_data>=8'h30&&byte_data<=8'h39;
 wire[3:0] digit_value=byte_data-8'h30;
 wire[38:0] total_frame_wide=({7'd0,minutes}<<12)+({7'd0,minutes}<<8)+
                             ({7'd0,minutes}<<7)+({7'd0,minutes}<<4)+
                             ({7'd0,minutes}<<2)+({32'd0,seconds}<<6)+
                             ({32'd0,seconds}<<3)+({32'd0,seconds}<<1)+
                             {32'd0,seconds}+{32'd0,frames};
 task finish_line;
 begin
  if(state==FRAMES&&index01&&digits!=0)begin
   if(seconds>=60||frames>=75||total_frame_wide[38:32]!=0||
      (track_count!=0&&total_frame_wide[31:0]<=last_frame)||track_count==99)error<=1;
   else begin
    track_write<=1;track_address<=track_count;track_frame<=total_frame_wide[31:0];
    track_count<=track_count+1'b1;last_frame<=total_frame_wide[31:0];
   end
  end
  state<=LINE;minutes<=0;seconds<=0;frames<=0;digits<=0;index01<=0;
 end
 endtask
 always @(posedge clk)begin
  track_write<=0;
  if(reset||!enable)begin
   state<=LINE;minutes<=0;seconds<=0;frames<=0;digits<=0;index01<=0;
   track_address<=0;track_frame<=0;track_count<=0;last_frame<=0;
   ready<=0;done<=0;error<=0;
  end else if(byte_valid&&!done)begin
   if(byte_eof)begin
    finish_line();done<=1;ready<=track_count!=0&&!error;
   end else if(newline)finish_line();
   else case(state)
    LINE:if(whitespace)state<=LINE;else state<=byte_data=="I"||byte_data=="i"?I:IGNORE;
    I:state<=byte_data=="N"||byte_data=="n"?N:IGNORE;
    N:state<=byte_data=="D"||byte_data=="d"?D:IGNORE;
    D:state<=byte_data=="E"||byte_data=="e"?E:IGNORE;
    E:state<=byte_data=="X"||byte_data=="x"?X:IGNORE;
    X:state<=whitespace?WS_INDEX:IGNORE;
    WS_INDEX:if(!whitespace)state<=digit?NUM0:IGNORE;
    NUM0:begin index01<=byte_data=="1";state<=digit?NUM1:IGNORE;end
    NUM1:state<=whitespace&&index01?WS_TIME:IGNORE;
    WS_TIME:if(!whitespace)begin
     if(digit)begin minutes<=digit_value;digits<=1;state<=MINUTES;end else state<=IGNORE;
    end
    MINUTES:if(digit)begin minutes<=minutes*10+digit_value;digits<=digits+1'b1;end
            else if(byte_data==":"&&digits!=0)begin digits<=0;state<=SECONDS;end else state<=IGNORE;
    SECONDS:if(digit)begin seconds<=seconds*10+digit_value;digits<=digits+1'b1;end
            else if(byte_data==":"&&digits!=0)begin digits<=0;state<=FRAMES;end else state<=IGNORE;
    FRAMES:if(digit)begin frames<=frames*10+digit_value;digits<=digits+1'b1;end
           else if(!whitespace)state<=IGNORE;
    default:state<=IGNORE;
   endcase
  end
 end
endmodule
