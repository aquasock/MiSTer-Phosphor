// Estimate a standalone stream duration from its byte size and advertised
// bitrate.  The serial multiply/divide is control-plane logic: no DSPs and no
// wide combinational divider are inferred.  Result units are 1/360000 second.
module media_duration_estimator(
 input wire clk,reset,start,input wire [63:0] file_size,
 input wire [31:0] bits_per_second,input wire [21:0] scale,
 output reg busy=0,valid=0,output reg [34:0] duration_q=0
);
 reg [6:0] multiply_count=0;
 reg [21:0] multiplier=0;
 reg [85:0] multiplicand=0,product=0;
 reg [6:0] divide_count=0;
 reg [31:0] divisor=1,remainder=0;
 reg [85:0] quotient=0;
 wire [32:0] trial={remainder,quotient[85]};
 wire [32:0] difference=trial-{1'b0,divisor};
 always @(posedge clk) begin
  if(reset)begin busy<=0;valid<=0;duration_q<=0;multiply_count<=0;divide_count<=0;end
  else begin
   if(start&&bits_per_second!=0&&!busy)begin
    busy<=1;valid<=0;multiplier<=scale;
    multiplicand<={22'd0,file_size};product<=0;multiply_count<=22;divide_count<=0;
    divisor<=bits_per_second;
   end else if(busy&&multiply_count!=0)begin
    if(multiplier[0])product<=product+multiplicand;
    multiplier<=multiplier>>1;multiplicand<=multiplicand<<1;
    multiply_count<=multiply_count-1'b1;
    if(multiply_count==1)begin
     quotient<=multiplier[0]?product+multiplicand:product;
     remainder<=0;divide_count<=86;
    end
   end else if(busy&&divide_count!=0)begin
    remainder<=difference[32]?trial[31:0]:difference[31:0];
    quotient<={quotient[84:0],!difference[32]};
    divide_count<=divide_count-1'b1;
    if(divide_count==1)begin
     busy<=0;valid<=1;
     duration_q<=|quotient[84:34]?{35{1'b1}}:
                 {quotient[33:0],!difference[32]};
    end
   end
  end
 end
endmodule
