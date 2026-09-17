// Stereo 2x reconstruction filter for the XY visualizer. A 15-tap half-band
// FIR is split into its two polyphase outputs: one phase is an exact delayed
// source sample, while the other uses four symmetric coefficient pairs. A
// single time-multiplexed multiplier handles both channels in eight clocks.
module media_xy_interpolator(
 input  wire clk,active,input wire sample_tick,
 input  wire signed [15:0] sample_left,sample_right,
 output reg output_tick=0,
 output reg signed [15:0] output_left=0,output_right=0
);
 reg signed [15:0] history_l[0:6];
 reg signed [15:0] history_r[0:6];
 reg signed [15:0] delayed_l=0,delayed_r=0;
 reg [3:0] state=0;
 reg signed [35:0] accumulator_l=0,accumulator_r=0;
 reg signed [16:0] pair_value;
 reg signed [15:0] coefficient;
 wire signed [32:0] product=pair_value*coefficient;

 // Coefficients are the nonzero phase of a unity-gain, 15-tap Hamming
 // half-band interpolator in Q1.15. Their symmetric sum is exactly 32768.
 always @* begin
  pair_value=0;coefficient=0;
  case(state)
   1: begin pair_value={sample_left[15],sample_left}+{history_l[6][15],history_l[6]};coefficient=-16'sd240;end
   2: begin pair_value={history_l[0][15],history_l[0]}+{history_l[5][15],history_l[5]};coefficient=16'sd1064;end
   3: begin pair_value={history_l[1][15],history_l[1]}+{history_l[4][15],history_l[4]};coefficient=-16'sd4500;end
   4: begin pair_value={history_l[2][15],history_l[2]}+{history_l[3][15],history_l[3]};coefficient=16'sd20060;end
   5: begin pair_value={sample_right[15],sample_right}+{history_r[6][15],history_r[6]};coefficient=-16'sd240;end
   6: begin pair_value={history_r[0][15],history_r[0]}+{history_r[5][15],history_r[5]};coefficient=16'sd1064;end
   7: begin pair_value={history_r[1][15],history_r[1]}+{history_r[4][15],history_r[4]};coefficient=-16'sd4500;end
   8: begin pair_value={history_r[2][15],history_r[2]}+{history_r[3][15],history_r[3]};coefficient=16'sd20060;end
   default: begin pair_value=0;coefficient=0;end
  endcase
 end

 function automatic signed [15:0] rounded_saturate(input signed [35:0] value);
  reg signed [35:0] rounded;
  begin
   rounded=value+(value>=0?36'sd16384:-36'sd16384);
   if(rounded>36'sd1073709056)rounded_saturate=16'sh7fff;
   else if(rounded< -36'sd1073741824)rounded_saturate=-16'sh8000;
   else rounded_saturate=rounded>>>15;
  end
 endfunction

 integer i;
 always @(posedge clk) begin
  output_tick<=0;
  if(!active)begin
   state<=0;accumulator_l<=0;accumulator_r<=0;
   output_left<=0;output_right<=0;delayed_l<=0;delayed_r<=0;
   for(i=0;i<7;i=i+1)begin history_l[i]<=0;history_r[i]<=0;end
  end else begin
   if(sample_tick&&state==0)begin
    delayed_l<=history_l[2];delayed_r<=history_r[2];
    for(i=6;i>0;i=i-1)begin history_l[i]<=history_l[i-1];history_r[i]<=history_r[i-1];end
    history_l[0]<=sample_left;history_r[0]<=sample_right;
    state<=1;
   end else if(state>=1&&state<=4)begin
    if(state==1)accumulator_l<=product;
    else accumulator_l<=accumulator_l+product;
    state<=state+1'b1;
   end else if(state>=5&&state<=8)begin
    if(state==5)accumulator_r<=product;
    else accumulator_r<=accumulator_r+product;
    state<=state+1'b1;
   end else if(state==9)begin
    output_left<=rounded_saturate(accumulator_l);
    output_right<=rounded_saturate(accumulator_r);
    output_tick<=1;state<=10;
   end else if(state==10)begin
    output_left<=delayed_l;output_right<=delayed_r;
    output_tick<=1;state<=0;
   end
  end
 end
endmodule
