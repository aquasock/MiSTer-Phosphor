// Expands a decoded Vorbis codebook entry into signed Q16.16 VQ values.
module vorbis_codebook_vector(
 input wire clk,input wire reset,input wire start,input wire [7:0] book,input wire [17:0] entry,
 output reg [7:0] codebook_query=0,input wire [15:0] codebook_dimensions,
 input wire [1:0] codebook_lookup_type,input wire codebook_sequence,
 input wire [31:0] codebook_minimum,input wire [31:0] codebook_delta,
 input wire [13:0] codebook_multiplicand_start,input wire [13:0] codebook_multiplicand_count,
 output reg [13:0] multiplicand_query_address=0,input wire [15:0] multiplicand_query_data,
 output wire ready,output reg value_valid=0,input wire value_ready,
 output reg [15:0] value_index=0,output reg signed [31:0] value=0,
 output reg done=0,output reg error=0
);
 localparam IDLE=0,QUERY_WAIT=1,SETUP=2,DIV_START=3,DIV_WAIT=4,VALUE_WAIT=5,EMIT=6,FINISH=7;
 reg [2:0] state=IDLE;
 reg [17:0] saved_entry=0;
 reg [15:0] dimension_index=0;
 reg [17:0] lookup_quotient=0;
 reg signed [31:0] minimum_q=0,delta_q=0,last_q=0;
 reg signed [48:0] product;
 reg signed [31:0] computed;
 assign ready=state==IDLE;
 function signed [31:0] unpack_q16;input [31:0] raw;integer shift;reg signed [63:0] wide;begin
  wide={43'd0,raw[20:0]};shift=raw[30:21]-788+16;
  if(shift>=0)wide=wide<<<shift;else wide=wide>>(-shift);
  unpack_q16=raw[31]?-wide[31:0]:wide[31:0];
 end endfunction
 wire divider_ready,divider_done,divider_error;
 wire [17:0] divider_quotient,divider_remainder;
 // Residue vector expansion performs thousands of these small divisions per
 // audio block. Resolve two quotient bits per clock for this even-width path;
 // the other Vorbis dividers retain the shorter one-bit combinational path.
 vorbis_unsigned_divider #(.WIDTH(18),.TRIPLE_STEP(1)) digit_divider(.clk(clk),.reset(reset),.start(state==DIV_START),
  .numerator(lookup_quotient),.denominator({4'd0,codebook_multiplicand_count}),
  .ready(divider_ready),.done(divider_done),.error(divider_error),
  .quotient(divider_quotient),.remainder(divider_remainder));
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;value_valid<=0;done<=0;error<=0;end
  else begin
   done<=0;if(value_valid&&value_ready)value_valid<=0;
   case(state)
    IDLE:if(start)begin codebook_query<=book;saved_entry<=entry;dimension_index<=0;lookup_quotient<=entry;last_q<=0;state<=QUERY_WAIT;end
    QUERY_WAIT:state<=SETUP;
    SETUP:begin
     minimum_q<=unpack_q16(codebook_minimum);delta_q<=unpack_q16(codebook_delta);
     if(codebook_dimensions==0||codebook_lookup_type==0||codebook_multiplicand_count==0)begin error<=1;state<=FINISH;end
     else if(codebook_lookup_type==1)state<=DIV_START;
     else begin multiplicand_query_address<=codebook_multiplicand_start+saved_entry*codebook_dimensions;state<=VALUE_WAIT;end
    end
    DIV_START:if(divider_ready)state<=DIV_WAIT;
    DIV_WAIT:if(divider_done)begin
     if(divider_error)begin error<=1;state<=FINISH;end
     else begin
      multiplicand_query_address<=codebook_multiplicand_start+divider_remainder[13:0];
      lookup_quotient<=divider_quotient;state<=VALUE_WAIT;
     end
    end
    VALUE_WAIT:state<=EMIT;
    EMIT:if(!value_valid)begin
     product=$signed({1'b0,multiplicand_query_data})*delta_q;
     computed=minimum_q+product;
     if(codebook_sequence)computed=computed+last_q;
     value<=computed;value_index<=dimension_index;value_valid<=1;
     if(codebook_sequence)last_q<=computed;
     if(dimension_index+1'b1==codebook_dimensions)state<=FINISH;
     else begin
      dimension_index<=dimension_index+1'b1;
      if(codebook_lookup_type==1)state<=DIV_START;
      else begin multiplicand_query_address<=multiplicand_query_address+1'b1;state<=VALUE_WAIT;end
     end
    end
    FINISH:if(!value_valid)begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
