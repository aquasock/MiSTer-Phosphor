// Small serialized unsigned divider. One quotient bit is resolved per clock,
// avoiding the large combinational dividers inferred from variable / and %.
module vorbis_unsigned_divider #(
 parameter WIDTH=24,parameter DOUBLE_STEP=0,parameter TRIPLE_STEP=0
)(
 input wire clk,input wire reset,input wire start,
 input wire [WIDTH-1:0] numerator,input wire [WIDTH-1:0] denominator,
 output wire ready,output reg done=0,output reg error=0,
 output reg [WIDTH-1:0] quotient=0,output reg [WIDTH-1:0] remainder=0
);
 reg busy=0;
 reg [WIDTH-1:0] numerator_shift=0,denominator_saved=0,quotient_work=0;
 reg [WIDTH:0] remainder_work=0;
 reg [$clog2(WIDTH+1)-1:0] bit_count=0;
 wire [WIDTH:0] shifted_remainder={remainder_work[WIDTH-1:0],numerator_shift[WIDTH-1]};
 wire subtract=shifted_remainder>={1'b0,denominator_saved};
 wire [WIDTH:0] first_remainder=subtract?shifted_remainder-{1'b0,denominator_saved}:shifted_remainder;
 wire [WIDTH:0] shifted_remainder_2={first_remainder[WIDTH-1:0],numerator_shift[WIDTH-2]};
 wire subtract_2=shifted_remainder_2>={1'b0,denominator_saved};
 wire [WIDTH:0] second_remainder=subtract_2?shifted_remainder_2-{1'b0,denominator_saved}:shifted_remainder_2;
 wire [WIDTH:0] shifted_remainder_3={second_remainder[WIDTH-1:0],numerator_shift[WIDTH-3]};
 wire subtract_3=shifted_remainder_3>={1'b0,denominator_saved};
 wire [WIDTH:0] third_remainder=subtract_3?shifted_remainder_3-{1'b0,denominator_saved}:shifted_remainder_3;
 assign ready=!busy;
 always @(posedge clk)begin
  if(reset)begin busy<=0;done<=0;error<=0;quotient<=0;remainder<=0;end
  else begin
   done<=0;
   if(start&&ready)begin
    if(denominator==0)begin error<=1;done<=1;quotient<=0;remainder<=numerator;end
    else begin
     busy<=1;error<=0;numerator_shift<=numerator;denominator_saved<=denominator;
     quotient_work<=0;remainder_work<=0;bit_count<=WIDTH;
   end
   end else if(busy)begin
    if(TRIPLE_STEP)begin
     numerator_shift<=numerator_shift<<3;
     remainder_work<=third_remainder;
     quotient_work<={quotient_work[WIDTH-4:0],subtract,subtract_2,subtract_3};
     bit_count<=bit_count-2'd3;
     if(bit_count<=3)begin
      busy<=0;done<=1;quotient<={quotient_work[WIDTH-4:0],subtract,subtract_2,subtract_3};
      remainder<=third_remainder;
     end
    end else if(DOUBLE_STEP)begin
     numerator_shift<=numerator_shift<<2;
     remainder_work<=second_remainder;
     quotient_work<={quotient_work[WIDTH-3:0],subtract,subtract_2};
     bit_count<=bit_count-2'd2;
     if(bit_count<=2)begin
      busy<=0;done<=1;quotient<={quotient_work[WIDTH-3:0],subtract,subtract_2};
      remainder<=second_remainder;
     end
    end else begin
     numerator_shift<=numerator_shift<<1;
     remainder_work<=first_remainder;
     quotient_work<={quotient_work[WIDTH-2:0],subtract};
     bit_count<=bit_count-1'b1;
     if(bit_count==1)begin
      busy<=0;done<=1;quotient<={quotient_work[WIDTH-2:0],subtract};
      remainder<=first_remainder;
     end
    end
   end
  end
 end
endmodule
