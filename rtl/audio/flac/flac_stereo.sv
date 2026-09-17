// Exact integer stereo decorrelation; inputs are coded channels, not L/R yet.
module flac_stereo(
 input wire [3:0] assignment_code,
 input wire signed[16:0] channel0,channel1,
 output wire signed[15:0] left,right,
 output wire error
);
 wire signed[18:0] x={{2{channel0[16]}},channel0};
 wire signed[18:0] y={{2{channel1[16]}},channel1};
 wire signed[18:0] mid=(x<<<1)|$signed({18'd0,channel1[0]});
 reg signed[18:0] l,r;reg valid_code;
 always @* begin
  valid_code=1;l=x;r=y;
  case(assignment_code)
   1:begin l=x;r=y;end
   8:begin l=x;r=x-y;end
   9:begin l=x+y;r=y;end
   10:begin l=(mid+y)>>>1;r=(mid-y)>>>1;end
   default:valid_code=0;
  endcase
 end
 assign left=l[15:0];assign right=r[15:0];
 assign error=!valid_code||l[18:15]!={4{l[15]}}||r[18:15]!={4{r[15]}};
endmodule
