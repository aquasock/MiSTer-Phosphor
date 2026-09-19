// Scan a bounded tail window for Ogg page headers and retain the final page's
// granule position.  The stream serial is already constrained by the decoder;
// this preflight only supplies exact duration before audible playback starts.
module media_ogg_tail_probe(
 input wire clk,reset,enable,input wire byte_valid,input wire [7:0] byte_data,input wire byte_eof,
 output reg valid=0,output reg [63:0] granule=0
);
 reg [2:0] match=0;
 reg [4:0] header_index=0;
 reg in_header=0;
 reg [63:0] candidate=0;
 always @(posedge clk)begin
  if(reset)begin match<=0;header_index<=0;in_header<=0;valid<=0;granule<=0;candidate<=0;end
  else if(enable&&byte_valid&&!byte_eof)begin
   if(in_header)begin
    if(header_index>=6&&header_index<=13)
     candidate[(header_index-6)*8 +: 8]<=byte_data;
    if(header_index==13)begin granule<={byte_data,candidate[55:0]};valid<=1;in_header<=0;match<=0;end
    else header_index<=header_index+1'b1;
   end else if((match==0&&byte_data=="O")||(match==1&&byte_data=="g")||
               (match==2&&byte_data=="g")||(match==3&&byte_data=="S"))begin
    if(match==3)begin in_header<=1;header_index<=4;match<=0;candidate<=0;end
    else match<=match+1'b1;
   end else match<=byte_data=="O"?1:0;
  end
 end
endmodule
