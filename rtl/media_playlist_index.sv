// Fixed-record accelerator stored as playlist.idx in a mixed-format TAR.
// Header: "MP3P", version 1, count, record size 24, reserved.
// Record: kind byte, 7 reserved, little-endian u64 TAR payload offset and size.
module media_playlist_index(
 input wire clk,reset,enable,byte_valid,input wire[7:0] byte_data,input wire byte_eof,
 output reg entry_write=0,output reg[6:0] entry_address=0,output reg[2:0] entry_kind=0,
 output reg[40:0] entry_offset=0,entry_size=0,output reg[6:0] entry_count=0,
 output reg ready=0,done=0,error=0
);
 reg[11:0] position=0;reg[7:0] count=0,record_size=0;reg[6:0] record_index=0;reg[63:0] field=0;
 wire[63:0] field_next={byte_data,field[63:8]};
 always @(posedge clk)begin
  entry_write<=0;
  if(reset||!enable)begin position<=0;count<=0;record_size<=0;record_index<=0;field<=0;entry_address<=0;
   entry_kind<=0;entry_offset<=0;entry_size<=0;entry_count<=0;ready<=0;done<=0;error<=0;
  end else if(byte_valid&&!done)begin
   if(byte_eof)begin done<=1;ready<=!error&&entry_count==count&&count!=0;end
   else begin
    position<=position+1'b1;
    if(position<4)begin
     if(byte_data!=(position==0?"M":position==1?"P":position==2?"3":"P"))error<=1;
    end else if(position==4&&byte_data!=1)error<=1;
    else if(position==5)begin count<=byte_data;entry_count<=byte_data<=99?byte_data:0;if(byte_data==0||byte_data>99)error<=1;end
    else if(position==6)begin record_size<=byte_data;if(byte_data!=24)error<=1;end
    else if(position>=8)begin
     field<=field_next;
     case((position-8)%24)
      0:begin entry_kind<=byte_data[2:0];if(byte_data<1||byte_data>4)error<=1;end
      15:begin entry_offset<=field_next[40:0];if(field_next[63:41]!=0)error<=1;end
      23:begin
       entry_size<=field_next[40:0];
       if(field_next==0||field_next[63:41]!=0||record_index>=count)error<=1;
       else begin entry_write<=1;entry_address<=record_index;record_index<=record_index+1'b1;end
      end
     endcase
    end
   end
  end
 end
endmodule
