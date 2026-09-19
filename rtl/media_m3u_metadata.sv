// Extended-M3U text capture for the mixed playlist UI. Recognizes the common
// #PLAYLIST:name album label and the title following each #EXTINF duration.
module media_m3u_metadata(
 input wire write_clk,reset,begin_file,byte_valid,input wire[7:0] byte_data,input wire byte_eof,
 output wire input_ready,output reg ready=0,
 input wire read_clk,input wire[13:0] read_address,input wire[7:0] current_track,
 output reg[7:0] read_data=0,output reg valid=0,output reg[7:0] track_count=0,
 output wire current_title_long
);
 localparam CLEAR=0,LINE=1,HASH=2,E=3,EX=4,EXT=5,EXTI=6,EXTIN=7,EXTINF=8,
  EXT_SKIP=9,TITLE=10,P=11,PL=12,PLA=13,PLAY=14,PLAYL=15,PLAYLI=16,PLAYLIS=17,
  PLAYLIST=18,ALBUM=19,IGNORE=20,A=21,AR=22,ART=23,ARTI=24,ARTIS=25,ARTIST=26,
  ARTIST_TEXT=27;
 reg[4:0] state=CLEAR;reg[13:0] clear_address=0,write_address=0,text_base=0;
 reg[5:0] text_length=0;reg[254:0] title_long=0;reg any_text=0;
 (* ramstyle="M10K" *) reg[7:0] bytes[0:8191];
 reg ram_write=0;reg[12:0] ram_address=0;reg[7:0] ram_data=0;
 wire newline=byte_data==8'h0a||byte_data==8'h0d;
 wire[7:0] upper=(byte_data>=8'h61&&byte_data<=8'h7a)?byte_data-8'h20:byte_data;
 assign input_ready=state!=CLEAR;
 assign current_title_long=valid&&current_track>=1?title_long[current_track-1'b1]:1'b0;
 always @(posedge read_clk)read_data<=bytes[read_address[12:0]];
 always @(posedge write_clk)if(ram_write)bytes[ram_address]<=ram_data;
 task finish_text;begin
  if(text_length!=0)any_text<=1;
  if(state==TITLE)begin ram_write<=1;ram_address<=text_base[12:0]+13'd30;ram_data<=text_length>30?8'd30:{2'd0,text_length};end
  else if(state==ALBUM)begin ram_write<=1;ram_address<=13'd39;ram_data<=text_length>31?8'd31:{2'd0,text_length};end
  else if(state==ARTIST_TEXT)begin ram_write<=1;ram_address<=13'd71;ram_data<=text_length>31?8'd31:{2'd0,text_length};end
  state<=LINE;text_length<=0;
 end endtask
 always @(posedge write_clk)begin
  ram_write<=0;
  if(reset)begin state<=LINE;clear_address<=0;write_address<=0;text_base<=0;text_length<=0;title_long<=0;any_text<=0;track_count<=0;ready<=0;valid<=0;end
  else if(begin_file)begin state<=CLEAR;clear_address<=0;write_address<=0;text_base<=0;text_length<=0;title_long<=0;any_text<=0;track_count<=0;ready<=0;valid<=0;end
  else if(state==CLEAR)begin
   ram_write<=1;ram_address<=clear_address[12:0];ram_data<=0;
   if(clear_address==8191)begin state<=LINE;clear_address<=0;end else clear_address<=clear_address+1'b1;
  end
  else if(byte_valid&&!ready)begin
   if(byte_eof)begin if(state==TITLE||state==ALBUM||state==ARTIST_TEXT)finish_text();ready<=1;valid<=any_text||text_length!=0;end
   else if(newline)begin if(state==TITLE||state==ALBUM||state==ARTIST_TEXT)finish_text();else state<=LINE;end
   else case(state)
    LINE:state<=byte_data=="#"?HASH:IGNORE;
    HASH:if(upper=="E")state<=E;else if(upper=="P")state<=P;else if(upper=="A")state<=A;else state<=IGNORE;
    E:state<=upper=="X"?EX:IGNORE; EX:state<=upper=="T"?EXT:IGNORE;
    EXT:state<=upper=="I"?EXTI:IGNORE; EXTI:state<=upper=="N"?EXTIN:IGNORE;
    EXTIN:state<=upper=="F"?EXTINF:IGNORE; EXTINF:state<=byte_data==":"?EXT_SKIP:IGNORE;
    EXT_SKIP:if(byte_data==","&&track_count<255)begin
     write_address<=14'd72+({6'd0,track_count}<<5)-track_count;
     text_base<=14'd72+({6'd0,track_count}<<5)-track_count;
     text_length<=0;state<=TITLE;track_count<=track_count+1'b1;
    end
    P:state<=upper=="L"?PL:IGNORE; PL:state<=upper=="A"?PLA:IGNORE;
    PLA:state<=upper=="Y"?PLAY:IGNORE; PLAY:state<=upper=="L"?PLAYL:IGNORE;
    PLAYL:state<=upper=="I"?PLAYLI:IGNORE; PLAYLI:state<=upper=="S"?PLAYLIS:IGNORE;
    PLAYLIS:state<=upper=="T"?PLAYLIST:IGNORE;
    PLAYLIST:if(byte_data==":")begin write_address<=14'd8;text_base<=14'd8;text_length<=0;state<=ALBUM;end else state<=IGNORE;
    A:state<=upper=="R"?AR:IGNORE; AR:state<=upper=="T"?ART:IGNORE;
    ART:state<=upper=="I"?ARTI:IGNORE; ARTI:state<=upper=="S"?ARTIS:IGNORE;
    ARTIS:state<=upper=="T"?ARTIST:IGNORE;
    ARTIST:if(byte_data==":")begin write_address<=14'd40;text_base<=14'd40;text_length<=0;state<=ARTIST_TEXT;end else state<=IGNORE;
    TITLE,ALBUM,ARTIST_TEXT:begin
     if(text_length<(state==TITLE?30:31))begin
      ram_write<=1;ram_address<=write_address[12:0];ram_data<=byte_data;write_address<=write_address+1'b1;
     end
     if(text_length<63)text_length<=text_length+1'b1;
     if(state==TITLE&&track_count!=0&&text_length>=15)title_long[track_count-1'b1]<=1;
    end
    default:state<=IGNORE;
   endcase
  end
 end
endmodule
