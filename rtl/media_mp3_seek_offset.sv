// Convert a requested presentation time into a near-by MP3 byte position.
// Starting 32 KiB early supplies ample bit-reservoir history; only that short
// preroll is silently decoded instead of replaying the whole song. Arithmetic
// is serialized so this control path consumes no DSP blocks.
module media_mp3_seek_offset(
 input wire clk,reset,start,input wire [40:0] file_size,
 input wire [34:0] target_q,duration_q,
 output reg busy=0,done=0,output reg [40:0] offset=0,
 output reg [34:0] preroll_q=0
);
 localparam IDLE=0,MULTIPLY=1,DIVIDE_OFFSET=2,DIVIDE_PREROLL=3;
 reg [1:0] state=IDLE;
 reg [6:0] count=0;
 reg [34:0] multiplier=0;
 reg [75:0] multiplicand=0,product=0,quotient=0;
 reg [40:0] divisor=1,remainder=0;
 reg [49:0] quotient2=0;
 wire [41:0] trial={remainder,quotient[75]};
 wire [41:0] difference=trial-{1'b0,divisor};
 wire [41:0] trial2={remainder,quotient2[49]};
 wire [41:0] difference2=trial2-{1'b0,divisor};
 wire [40:0] byte_result={quotient[39:0],!difference[41]};
 wire [49:0] preroll_result={quotient2[48:0],!difference2[41]};
 always @(posedge clk)begin
  done<=0;
  if(reset)begin state<=IDLE;busy<=0;offset<=0;preroll_q<=0;count<=0;end
  else case(state)
   IDLE:if(start&&file_size!=0&&duration_q!=0)begin
    busy<=1;multiplier<=target_q;multiplicand<={35'd0,file_size};product<=0;count<=35;state<=MULTIPLY;
   end
   MULTIPLY:begin
    if(multiplier[0])product<=product+multiplicand;
    multiplier<=multiplier>>1;multiplicand<=multiplicand<<1;count<=count-1'b1;
    if(count==1)begin
     quotient<=multiplier[0] ? product+multiplicand : product;
     remainder<=0;divisor<={6'd0,duration_q};count<=76;state<=DIVIDE_OFFSET;
    end
   end
   DIVIDE_OFFSET:begin
    remainder<=difference[41] ? trial[40:0] : difference[40:0];
    quotient<={quotient[74:0],!difference[41]};count<=count-1'b1;
    if(count==1)begin
     if(byte_result<=41'd32768)begin
      offset<=0;preroll_q<=target_q;busy<=0;done<=1;state<=IDLE;
     end else begin
      offset<=byte_result-41'd32768;
      quotient2<={duration_q,15'd0};remainder<=0;divisor<=file_size;count<=50;state<=DIVIDE_PREROLL;
     end
    end
   end
   DIVIDE_PREROLL:begin
    remainder<=difference2[41] ? trial2[40:0] : difference2[40:0];
    quotient2<=preroll_result;count<=count-1'b1;
    if(count==1)begin
     preroll_q<=|preroll_result[49:35] ? {35{1'b1}} : preroll_result[34:0];
     busy<=0;done<=1;state<=IDLE;
    end
   end
   default:begin state<=IDLE;busy<=0;end
  endcase
 end
endmodule
