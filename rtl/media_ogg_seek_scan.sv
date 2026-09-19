// Fast seek helper for a single logical Ogg stream. It scans compressed page
// headers rather than decoding audio and returns the page preceding the page
// whose completed-sample granule reaches the requested time. Starting one page
// early gives Vorbis overlap-add state time to settle before audio is unmuted.
module media_ogg_seek_scan(
 input wire clk,reset,enable,
 input wire [63:0] target_granule,input wire [63:0] byte_position,
 input wire byte_valid,input wire [7:0] byte_data,input wire byte_eof,
 output reg done=0,output reg [63:0] start_offset=0
);
 localparam SYNC=0,HEADER=1,LACES=2,BODY=3;
 reg [1:0] state=SYNC;
 reg [2:0] match=0;
 reg [4:0] header_index=0;
 reg [7:0] segments=0,lace_index=0;
 reg [15:0] body_bytes=0;
 reg [63:0] page_start=0,page_granule=0;
 reg [63:0] prior_offset=0,older_offset=0;
 reg have_prior=0,have_older=0;
 always @(posedge clk) begin
  if(reset||!enable)begin
   state<=SYNC;match<=0;header_index<=0;segments<=0;lace_index<=0;
   body_bytes<=0;page_start<=0;page_granule<=0;prior_offset<=0;older_offset<=0;
   have_prior<=0;have_older<=0;done<=0;start_offset<=0;
  end else if(byte_valid&&!done)begin
   if(byte_eof)begin done<=1;start_offset<=have_older?older_offset:64'd0;end
   else case(state)
    SYNC:begin
     if((match==0&&byte_data=="O")||(match==1&&byte_data=="g")||
        (match==2&&byte_data=="g")||(match==3&&byte_data=="S"))begin
      if(match==3)begin
       page_start<=byte_position-4;header_index<=4;page_granule<=0;state<=HEADER;match<=0;
      end else match<=match+1'b1;
     end else match<=byte_data=="O"?1:0;
    end
    HEADER:begin
     if(header_index>=6&&header_index<=13)
      page_granule[(header_index-6)*8 +: 8]<=byte_data;
     if(header_index==26)begin
      segments<=byte_data;lace_index<=0;body_bytes<=0;
      if(page_granule>=target_granule&&have_prior)begin
       done<=1;start_offset<=have_older?older_offset:prior_offset;
      end else if(byte_data==0)begin
       older_offset<=prior_offset;have_older<=have_prior;
       prior_offset<=page_start;have_prior<=1;state<=SYNC;
      end else state<=LACES;
     end else header_index<=header_index+1'b1;
    end
    LACES:begin
     body_bytes<=body_bytes+byte_data;lace_index<=lace_index+1'b1;
     if(lace_index+1'b1==segments)begin
      if(body_bytes+byte_data==0)begin
       older_offset<=prior_offset;have_older<=have_prior;
       prior_offset<=page_start;have_prior<=1;state<=SYNC;
      end else state<=BODY;
     end
    end
    BODY:begin
     body_bytes<=body_bytes-1'b1;
     if(body_bytes==1)begin
      older_offset<=prior_offset;have_older<=have_prior;
      prior_offset<=page_start;have_prior<=1;state<=SYNC;
     end
    end
   endcase
  end
 end
endmodule

// Small iterative arithmetic unit: floor(time_q * sample_rate / 360000).
// It deliberately uses one add/shift per clock so seeking consumes no DSPs.
module media_ogg_seek_granule(
 input wire clk,reset,start,input wire [34:0] time_q,input wire [31:0] sample_rate,
 output reg busy=0,done=0,output reg [63:0] granule=0
);
 reg [6:0] count=0;
 reg [34:0] multiplier=0;
 reg [66:0] multiplicand=0;
 reg [66:0] product=0;
 reg [66:0] dividend=0;
 reg [18:0] divisor=19'd360000;
 reg [63:0] quotient=0;
 reg [19:0] remainder=0;
 reg dividing=0;
 always @(posedge clk)begin
  done<=0;
  if(reset)begin busy<=0;dividing<=0;count<=0;granule<=0;end
  else if(start&&!busy)begin busy<=1;dividing<=0;count<=0;multiplier<=time_q;multiplicand<={35'd0,sample_rate};product<=0;end
  else if(busy&&!dividing)begin
   if(multiplier[0])product<=product+multiplicand;
   multiplier<=multiplier>>1;
   multiplicand<=multiplicand<<1;
   if(count==34)begin
    dividend<=multiplier[0]?product+multiplicand:product;
    count<=66;quotient<=0;remainder<=0;dividing<=1;
   end else count<=count+1'b1;
  end else if(busy)begin
   if({remainder[18:0],dividend[count]}>={1'b0,divisor})begin
    remainder<={remainder[18:0],dividend[count]}-{1'b0,divisor};quotient[count]<=1;
   end else remainder<={remainder[18:0],dividend[count]};
   if(count==0)begin granule<=quotient;granule[0]<=({remainder[18:0],dividend[0]}>={1'b0,divisor});busy<=0;done<=1;dividing<=0;end
   else count<=count-1'b1;
  end
 end
endmodule
