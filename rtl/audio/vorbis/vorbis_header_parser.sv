// Validates the three mandatory Vorbis header packets and publishes the
// stream profile needed to size and clock the decode pipeline.
module vorbis_header_parser(
 input wire clk,input wire reset,
 input wire packet_valid,input wire [7:0] packet_data,
 input wire packet_start,input wire packet_end,input wire packet_enable,output wire packet_ready,
 output reg identification_valid=0,output reg headers_valid=0,
 output reg [7:0] channels=0,output reg [31:0] sample_rate=0,
 output reg [31:0] bitrate_nominal=0,
 output reg [11:0] blocksize_short=0,blocksize_long=0,
 output reg [1:0] header_number=0,output reg error=0
);
 reg [31:0] index=0;
 reg packet_bad=0;
 reg [3:0] short_exp=0,long_exp=0;
 assign packet_ready=1'b1;
 function signature_ok;
  input [31:0] position;input [7:0] value;
  begin case(position)
   1:signature_ok=value=="v";2:signature_ok=value=="o";
   3:signature_ok=value=="r";4:signature_ok=value=="b";
   5:signature_ok=value=="i";6:signature_ok=value=="s";
   default:signature_ok=1'b1;
  endcase end
 endfunction
 always @(posedge clk)begin
  if(reset)begin
   identification_valid<=0;headers_valid<=0;channels<=0;sample_rate<=0;bitrate_nominal<=0;
   blocksize_short<=0;blocksize_long<=0;header_number<=0;index<=0;packet_bad<=0;error<=0;
  end else if(packet_valid&&packet_enable&&!headers_valid)begin
   if(packet_start)begin index<=0;packet_bad<=0;end
   if((packet_start?0:index)==0)begin
    if(packet_data!=(header_number==0?8'd1:header_number==1?8'd3:8'd5))packet_bad<=1;
   end else if(!signature_ok(packet_start?0:index,packet_data))packet_bad<=1;
   if(header_number==0)begin
    case(packet_start?0:index)
     7,8,9,10:if(packet_data!=0)packet_bad<=1;
     11:begin channels<=packet_data;if(packet_data==0||packet_data>2)packet_bad<=1;end
     12:sample_rate[7:0]<=packet_data;13:sample_rate[15:8]<=packet_data;
     14:sample_rate[23:16]<=packet_data;15:sample_rate[31:24]<=packet_data;
     20:bitrate_nominal[7:0]<=packet_data;21:bitrate_nominal[15:8]<=packet_data;
     22:bitrate_nominal[23:16]<=packet_data;23:bitrate_nominal[31:24]<=packet_data;
     28:begin short_exp<=packet_data[3:0];long_exp<=packet_data[7:4];
      if(packet_data[3:0]<6||packet_data[7:4]<packet_data[3:0]||packet_data[7:4]>11)packet_bad<=1;
     end
     29:if(!packet_data[0])packet_bad<=1;
    endcase
   end
   if(packet_end)begin
    if(header_number==0)begin
     if((packet_start?0:index)!=29)packet_bad<=1;
     if(!(packet_bad||((packet_start?0:index)!=29)||!packet_data[0]||
          (sample_rate!=44100&&sample_rate!=48000)))begin
      identification_valid<=1;
      blocksize_short<=12'd1<<short_exp;blocksize_long<=12'd1<<long_exp;
     end else error<=1;
    end else if(header_number==2)begin
     // The setup framing bit is bit-packed after a variable number of mode
     // fields; it is not necessarily bit zero of the packet's final byte.
     // The setup decoder validates it once those fields are consumed.
     if(!packet_bad&&identification_valid)headers_valid<=1;
    end
    if(packet_bad)error<=1;
    if(header_number<2)header_number<=header_number+1'b1;
    index<=0;
   end else index<=(packet_start?0:index)+1'b1;
  end
 end
endmodule
