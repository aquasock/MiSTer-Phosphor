// Streamed RFC 9639 subframe decoder for 16/17-bit coded CD channels.
// Output samples are provisional: outer frame CRC must pass before playback.
// Outer framing owns byte-to-bit conversion, stereo decorrelation and EOF.
module flac_subframe (
 input wire clk,reset,start,
 input wire [15:0] block_size,
 input wire [4:0] channel_bits,
 input wire bit_valid,bit_data,bit_end,
 output wire bit_ready,
 output wire sample_valid,
 input wire sample_ready,
 output wire signed [16:0] sample_data,
 output reg done,error
);
 localparam IDLE=0,GET=1,HEADER=2,WASTED=3,BEGIN_TYPE=4,VALUE=5,EMIT=6,
  WARM=7,PREC=8,SHIFT=9,COEFF=10,FIXED=11,METHOD=12,PART_ORDER=13,
  PARAM=14,ESC_WIDTH=15,RES_START=16,UNARY=17,REMAINDER=18,ESC_VALUE=19,
  MAC_START=20,PRIME=21,TAP=22,MAC_WAIT=23,FAILED=24;
 reg[4:0] state,return_state;
 reg[5:0] bits_left;
 reg[31:0] field;reg[30:0] acc;
 reg[5:0] kind,order,coeff_index;
 reg[4:0] nominal,bps,wasted,precision;
 reg[3:0] prediction_shift;
 reg[15:0] size,index,partition_size,residual_left;
 reg method,escaped;
 reg[4:0] rice,escape_width;
 reg[31:0] quotient;
 reg signed[31:0] residual;
 reg signed[16:0] raw_sample;
 reg[4:0] history_ptr,tap_index;
 (* ramstyle="M10K" *) reg signed[16:0] history[0:31];
 (* ramstyle="M10K" *) reg signed[15:0] coefficients[0:31];
 reg signed[16:0] history_q;reg signed[15:0] coefficient_q;
 wire[4:0] history_address=history_ptr-5'd1-tap_index;
 always @(posedge clk)begin
  history_q<=history[history_address];coefficient_q<=coefficients[tap_index];
 end
 function automatic signed[31:0] signed_field(input[31:0] v,input[5:0] n);
  signed_field=n==0 ? 32'sd0:($signed(v<<(32-n)) >>> (32-n));
 endfunction
 function automatic signed[15:0] fixed_coefficient(input[5:0] o,input[5:0] i);
  begin
   fixed_coefficient=0;
   case(o)
    1:fixed_coefficient=1;
    2:fixed_coefficient=i==0?2:-1;
    3:fixed_coefficient=i==0?3:i==1?-3:1;
    4:fixed_coefficient=i==0?4:i==1?-6:i==2?4:-1;
   endcase
  end
 endfunction
 task automatic read_bits(input[5:0] n,input[4:0] next_state);
  begin acc<=0;bits_left<=n;return_state<=next_state;
   if(n==0)begin field<=0;state<=next_state;end else state<=GET;
  end
 endtask
 task automatic fail;begin error<=1;state<=FAILED;end endtask
 wire mac_valid,mac_error,mac_ready;wire signed[16:0] mac_sample;
 flac_predict_mac mac(.clk(clk),.reset(reset||state==IDLE),.start(state==MAC_START),
  .order(order),.shift(prediction_shift),.residual(residual),.side_channel(nominal==17),
  .tap_valid(state==TAP),.tap_ready(mac_ready),.history(history_q),.coefficient(coefficient_q),
  .busy(),.result_valid(mac_valid),.result_ready(state==MAC_WAIT),.result(mac_sample),.error(mac_error));
 wire signed[39:0] restored=$signed({{23{raw_sample[16]}},raw_sample}) <<< wasted;
 wire fits=nominal==17 ? restored[39:16]=={24{restored[16]}} : restored[39:15]=={25{restored[15]}};
 wire[31:0] folded=(quotient<<rice)|field;
 wire[15:0] part_size_new=size>>field[3:0];
 wire[15:0] partition_mask=(16'hffff>>(16-field[3:0]));
 assign bit_ready=state==GET&&!reset;
 assign sample_valid=state==EMIT&&fits&&!reset;
 assign sample_data=restored[16:0];
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;return_state<=IDLE;bits_left<=0;field<=0;acc<=0;
   kind<=0;order<=0;coeff_index<=0;nominal<=0;bps<=0;wasted<=0;precision<=0;
   prediction_shift<=0;size<=0;index<=0;partition_size<=0;residual_left<=0;
   method<=0;escaped<=0;rice<=0;escape_width<=0;quotient<=0;residual<=0;
   raw_sample<=0;history_ptr<=0;tap_index<=0;done<=0;error<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     size<=block_size;nominal<=channel_bits;bps<=channel_bits;wasted<=0;
     index<=0;history_ptr<=0;prediction_shift<=0;error<=0;
     if(block_size==0||(channel_bits!=16&&channel_bits!=17))fail();
     else read_bits(8,HEADER);
    end
    GET:if(bit_valid)begin
     acc<={acc[29:0],bit_data};bits_left<=bits_left-1'b1;
     if(bits_left==1)begin field<={acc[30:0],bit_data};state<=return_state;end
    end else if(bit_end)fail();
    HEADER:begin
     kind<=field[6:1];order<=field[6]?{1'b0,field[5:1]}+6'd1:{3'd0,field[3:1]};
     if(field[7]||!((field[6:1]<=1)||(field[6:1]>=8&&field[6:1]<=12)||field[6]))fail();
     else if(field[0])begin wasted<=1;read_bits(1,WASTED);end
     else state<=BEGIN_TYPE;
    end
    WASTED:if(field[0])begin bps<=nominal-wasted;state<=BEGIN_TYPE;end
     else if(wasted>=nominal-1'b1)fail();
     else begin wasted<=wasted+1'b1;read_bits(1,WASTED);end
    BEGIN_TYPE:if(kind<=1)read_bits({1'b0,bps},VALUE);
     else if({10'd0,order}>=size)fail();
     else if(order!=0)read_bits({1'b0,bps},WARM);
     else begin coeff_index<=0;read_bits(2,METHOD);end
    VALUE:begin raw_sample<=17'(signed_field(field,{1'b0,bps}));state<=EMIT;end
    WARM:begin raw_sample<=17'(signed_field(field,{1'b0,bps}));state<=EMIT;end
    EMIT:if(!fits)fail();else if(sample_ready)begin
     history[history_ptr]<=raw_sample;history_ptr<=history_ptr+1'b1;index<=index+1'b1;
     if(index==size-1'b1)begin done<=1;state<=IDLE;end
     else if(kind==0)state<=EMIT;
     else if(kind==1)read_bits({1'b0,bps},VALUE);
     else if(index+1<order)read_bits({1'b0,bps},WARM);
     else if(index+16'd1=={10'd0,order})begin
      coeff_index<=0;
      if(kind[5])read_bits(4,PREC);else state<=FIXED;
     end else if(residual_left==1)begin
      residual_left<=partition_size;read_bits(method?6'd5:6'd4,PARAM);
     end else begin residual_left<=residual_left-1'b1;state<=RES_START;end
    end
    PREC:if(field==15)fail();else begin precision<=field[4:0]+1'b1;read_bits(5,SHIFT);end
    SHIFT:if(field[4])fail();else begin prediction_shift<=field[3:0];read_bits({1'b0,precision},COEFF);end
    COEFF:begin
     coefficients[coeff_index[4:0]]<=16'(signed_field(field,{1'b0,precision}));coeff_index<=coeff_index+1'b1;
     if(coeff_index+6'd1==order)read_bits(2,METHOD);else read_bits({1'b0,precision},COEFF);
    end
    FIXED:begin
     coefficients[coeff_index[4:0]]<=fixed_coefficient(order,coeff_index);coeff_index<=coeff_index+1'b1;
     if(coeff_index+6'd1==order)read_bits(2,METHOD);
    end
    METHOD:if(field>1)fail();else begin method<=field[0];read_bits(4,PART_ORDER);end
    PART_ORDER:if((size&partition_mask)!=0||part_size_new<={10'd0,order})fail();
     else begin partition_size<=part_size_new;residual_left<=part_size_new-{10'd0,order};read_bits(method?6'd5:6'd4,PARAM);end
    PARAM:begin
     rice<=field[4:0];escaped<=field==(method?31:15);
     if(field==(method?31:15))read_bits(5,ESC_WIDTH);else state<=RES_START;
    end
    ESC_WIDTH:begin escape_width<=field[4:0];state<=RES_START;end
    RES_START:if(escaped)read_bits({1'b0,escape_width},ESC_VALUE);
     else begin quotient<=0;read_bits(1,UNARY);end
    UNARY:if(field[0])read_bits({1'b0,rice},REMAINDER);
     else if(quotient >= (32'hfffffffe>>rice))fail();
     else begin quotient<=quotient+1'b1;read_bits(1,UNARY);end
    REMAINDER:if(folded==32'hffffffff)fail();else begin
     residual<=folded[0]?-$signed({1'b0,folded[31:1]})-32'sd1:$signed({1'b0,folded[31:1]});state<=MAC_START;
    end
    ESC_VALUE:begin residual<=signed_field(field,{1'b0,escape_width});state<=MAC_START;end
    MAC_START:begin tap_index<=0;state<=order==0?MAC_WAIT:PRIME;end
    PRIME:state<=TAP;
    TAP:if(mac_ready)begin
     tap_index<=tap_index+1'b1;state<=({1'b0,tap_index}+1==order)?MAC_WAIT:PRIME;
    end
    MAC_WAIT:if(mac_valid)begin if(mac_error)fail();else begin raw_sample<=mac_sample;state<=EMIT;end end
    FAILED:state<=FAILED;
    default:fail();
   endcase
  end
 end
endmodule
