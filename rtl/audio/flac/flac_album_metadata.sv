// Reads the fixed MP3A FLAC APPLICATION block produced by the companion
// builder. The dual-clock byte RAM lets the native video renderer fetch text
// and RGB332 artwork without involving or stalling the decoder.
module flac_album_metadata(
 input wire write_clk,reset,new_file,enabled,byte_valid,
 input wire [7:0] byte_data,
 input wire external_art_begin,external_art_valid,input wire [7:0] external_art_data,
 input wire external_art_eof,
 input wire read_clk,input wire [13:0] read_address,
 input wire [6:0] current_track,
 output reg [7:0] read_data=0,
 output reg valid=0,output reg artwork_valid=0,output reg [6:0] track_count=0,
 output wire current_title_long
);
 localparam MAGIC=0,HEADER=1,BODY=2,DONE=3;
 localparam APP_LENGTH=24'd11704;
 reg [1:0] state=MAGIC;
 reg [1:0] header_byte=0;
 reg [23:0] header=0,remaining=0,block_position=0;
 reg [6:0] block_type=0;
 reg block_last=0,app_candidate=0,app_good=0;
 reg [7:0] app_version=0;
 reg [13:0] external_art_count=0;
 reg [98:0] title_long=0;
 (* ramstyle="M10K" *) reg [7:0] bytes[0:11703];

 always @(posedge read_clk)read_data<=bytes[read_address];
 assign current_title_long=valid&&current_track>=1&&current_track<=99?
  title_long[current_track-1'b1]:1'b0;

 always @(posedge write_clk) begin
  if(reset||new_file) begin
   state<=MAGIC;header_byte<=0;header<=0;remaining<=0;block_position<=0;
   block_type<=0;block_last<=0;app_candidate<=0;app_good<=0;app_version<=0;
   valid<=0;artwork_valid<=0;track_count<=0;title_long<=0;external_art_count<=0;
  end else if(external_art_begin)begin
   external_art_count<=0;artwork_valid<=0;
  end else if(external_art_valid&&external_art_count<14'd8464)begin
   bytes[14'd3240+external_art_count]<=external_art_data;
   external_art_count<=external_art_count+1'b1;
  end else if(external_art_eof)begin
   artwork_valid<=external_art_count==14'd8464;
  end else if(byte_valid&&enabled&&state!=DONE) begin
   case(state)
    MAGIC:begin
     header<={header[15:0],byte_data};header_byte<=header_byte+1'b1;
     if(header_byte==3)begin
      state<=({header[23:0],byte_data}==32'h664c6143) ? HEADER : DONE;
      header_byte<=0;
     end
    end
    HEADER:begin
     header<={header[15:0],byte_data};header_byte<=header_byte+1'b1;
     if(header_byte==3)begin
      block_type<=header[22:16];block_last<=header[23];
      remaining<={header[15:0],byte_data};block_position<=0;
      app_candidate<=header[22:16]==2&&{header[15:0],byte_data}==APP_LENGTH;
      app_good<=header[22:16]==2&&{header[15:0],byte_data}==APP_LENGTH;
      header_byte<=0;
      if({header[15:0],byte_data}==0)state<=header[23]?DONE:HEADER;
      else state<=BODY;
     end
    end
    BODY:begin
     if(app_candidate)begin
      bytes[block_position[13:0]]<=byte_data;
      if(block_position>=103&&block_position<=3239&&block_position[4:0]==5'd7)
       title_long[(block_position-103)>>5]<=app_version==1?byte_data[0]:byte_data>15;
      case(block_position)
       0:if(byte_data!="M")app_good<=0;
       1:if(byte_data!="P")app_good<=0;
       2:if(byte_data!="3")app_good<=0;
       3:if(byte_data!="A")app_good<=0;
       4:begin app_version<=byte_data;if(byte_data!=1&&byte_data!=2)app_good<=0;end
       5:track_count<=byte_data<=99?byte_data:0;
       6:artwork_valid<=byte_data[0];
      endcase
     end
     block_position<=block_position+1'b1;remaining<=remaining-1'b1;
     if(remaining==1)begin
      if(app_candidate&&app_good&&block_position==11703&&track_count!=0)valid<=1;
      state<=block_last?DONE:HEADER;
     end
    end
    default:state<=DONE;
   endcase
  end
 end
endmodule
