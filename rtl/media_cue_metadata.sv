// Streams album and track text from the external CUE into the byte layout
// already consumed by media_flac_album_ui.  The RAM is cleared before the CUE
// payload is accepted, so shorter strings from a later album cannot expose
// stale characters.  Only the portable quoted TITLE/PERFORMER subset is
// needed; INDEX timing is parsed independently by media_cue_index.
module media_cue_metadata(
 input wire write_clk,reset,begin_file,byte_valid,input wire[7:0] byte_data,input wire byte_eof,
 output wire input_ready,output reg ready=0,
 input wire read_clk,input wire[13:0] read_address,input wire[6:0] current_track,
 output reg[7:0] read_data=0,output reg valid=0,output wire current_title_long
);
 localparam CLEAR_LAST=14'd4095;
 localparam LINE=0,T=1,TR=2,TRA=3,TRAC=4,TRACK_WS=5,TRACK_NUM=6,
            TI=7,TIT=8,TITL=9,TITLE_WS=10,TITLE_TEXT=11,
            P=12,PE=13,PER=14,PERF=15,PERFO=16,PERFOR=17,PERFORM=18,
            PERFORME=19,PERFORMER_WS=20,PERFORMER_TEXT=21,IGNORE=22;
 reg[4:0] state=LINE;
 reg clearing=0,saw_track=0,escape=0;
 reg[13:0] clear_address=0,write_address=0;
 reg[6:0] track_number=0;
 reg[5:0] text_length=0;
 reg any_text=0;
 reg[98:0] title_long=0;
 (* ramstyle="M10K" *) reg[7:0] bytes[0:4095];
 wire newline=byte_data==8'h0a||byte_data==8'h0d;
 wire whitespace=byte_data==8'h20||byte_data==8'h09;
 wire digit=byte_data>=8'h30&&byte_data<=8'h39;
 wire[7:0] upper=(byte_data>=8'h61&&byte_data<=8'h7a)?byte_data-8'h20:byte_data;
 assign input_ready=!clearing;
 assign current_title_long=valid&&current_track>=1&&current_track<=99?
                           title_long[current_track-1'b1]:1'b0;
 always @(posedge read_clk)read_data<=bytes[read_address[11:0]];
 task start_text(input performer);
 begin
  text_length<=0;escape<=0;
  if(performer)write_address<=14'd40;
  else if(saw_track&&track_number>=1&&track_number<=99)
   write_address<=14'd72+(track_number-1'b1)*32;
  else write_address<=14'd8;
 end
 endtask
 always @(posedge write_clk)begin
  if(reset)begin
   state<=LINE;clearing<=0;clear_address<=0;saw_track<=0;track_number<=0;
   write_address<=0;text_length<=0;escape<=0;any_text<=0;title_long<=0;
   ready<=0;valid<=0;
  end else if(begin_file)begin
   state<=LINE;clearing<=1;clear_address<=0;saw_track<=0;track_number<=0;
   write_address<=0;text_length<=0;escape<=0;any_text<=0;title_long<=0;
   ready<=0;valid<=0;
  end else if(clearing)begin
   bytes[clear_address]<=0;
   if(clear_address==CLEAR_LAST)begin clearing<=0;clear_address<=0;end
   else clear_address<=clear_address+1'b1;
  end else if(byte_valid&&!ready)begin
   if(byte_eof)begin ready<=1;valid<=any_text;state<=LINE;end
   else if(newline)begin state<=LINE;escape<=0;end
   else case(state)
    LINE:if(!whitespace)begin
     if(upper=="T")state<=T;else if(upper=="P")state<=P;else state<=IGNORE;
    end
    T:if(upper=="R")state<=TR;else if(upper=="I")state<=TI;else state<=IGNORE;
    TR:state<=upper=="A"?TRA:IGNORE;
    TRA:state<=upper=="C"?TRAC:IGNORE;
    TRAC:state<=upper=="K"?TRACK_WS:IGNORE;
    TRACK_WS:if(!whitespace)begin
     if(digit)begin track_number<=byte_data-"0";state<=TRACK_NUM;end else state<=IGNORE;
    end
    TRACK_NUM:begin
     if(digit&&track_number<100)track_number<=track_number*10+(byte_data-"0");
     else if(whitespace)begin saw_track<=track_number>=1&&track_number<=99;state<=IGNORE;end
     else state<=IGNORE;
    end
    TI:state<=upper=="T"?TIT:IGNORE;
    TIT:state<=upper=="L"?TITL:IGNORE;
    TITL:state<=upper=="E"?TITLE_WS:IGNORE;
    TITLE_WS:if(!whitespace)begin
     if(byte_data==8'h22)begin start_text(1'b0);state<=TITLE_TEXT;end else state<=IGNORE;
    end
    P:state<=upper=="E"?PE:IGNORE;
    PE:state<=upper=="R"?PER:IGNORE;
    PER:state<=upper=="F"?PERF:IGNORE;
    PERF:state<=upper=="O"?PERFO:IGNORE;
    PERFO:state<=upper=="R"?PERFOR:IGNORE;
    PERFOR:state<=upper=="M"?PERFORM:IGNORE;
    PERFORM:state<=upper=="E"?PERFORME:IGNORE;
    PERFORME:state<=upper=="R"?PERFORMER_WS:IGNORE;
    PERFORMER_WS:if(!whitespace)begin
     // Track-level performer is intentionally ignored: the compact info
     // panel displays the album performer, matching the old UI contract.
     if(byte_data==8'h22&&!saw_track)begin start_text(1'b1);state<=PERFORMER_TEXT;end
     else state<=IGNORE;
    end
    TITLE_TEXT,PERFORMER_TEXT:begin
     if(byte_data==8'h22&&!escape)begin state<=IGNORE;any_text<=any_text||(text_length!=0);end
     else begin
      escape<=byte_data==8'h5c&&!escape;
      if(byte_data!=8'h5c||escape)begin
       if(text_length<(state==TITLE_TEXT&&saw_track?24:15))begin
        bytes[write_address]<=byte_data;write_address<=write_address+1'b1;
       end
       if(text_length<63)text_length<=text_length+1'b1;
       if(state==TITLE_TEXT&&saw_track&&track_number>=1&&track_number<=99&&text_length>=15)
        title_long[track_number-1'b1]<=1;
      end
     end
    end
    default:state<=IGNORE;
   endcase
  end
 end
endmodule
