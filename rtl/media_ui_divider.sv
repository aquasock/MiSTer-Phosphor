// One restoring divider shared by scene formatting and layout, never pixels.
// Each quotient bit uses low-half subtract, high-half subtract, then restore.
// No 35-bit compare/subtract/mux cascade runs on the HDMI pixel clock.
module media_ui_divider(
 input wire clk,ce,start,input wire [47:0] numerator,input wire [34:0] denominator,
 output reg busy=0,output reg done=0,output reg [47:0] quotient=0,
 output reg [34:0] remainder=0
);
reg [34:0] divisor=1;
reg [5:0] count=0;
reg [1:0] phase=0;
reg [35:0] difference=0;
reg low_borrow=0,borrow=0;
wire [35:0] trial={remainder,quotient[47]};
wire [18:0] low_result={1'b0,trial[17:0]}-{1'b0,divisor[17:0]};
wire [18:0] high_result={1'b0,trial[35:18]}-{2'b00,divisor[34:18]}-{18'd0,low_borrow};
always @(posedge clk) if(ce) begin
 done<=0;
 if(start && !busy) begin
  quotient<=numerator;divisor<=denominator;remainder<=0;count<=48;busy<=1;phase<=0;
 end else if(busy) begin
  case(phase)
   0:begin difference[17:0]<=low_result[17:0];low_borrow<=low_result[18];phase<=1;end
   1:begin difference[35:18]<=high_result[17:0];borrow<=high_result[18];phase<=2;end
   2:begin
    // Trial stays stable until this commit, so restoration needs no duplicate
    // remainder register. The caller supplies a nonzero denominator.
    remainder<=borrow?trial[34:0]:difference[34:0];
    quotient<={quotient[46:0],!borrow};phase<=0;count<=count-1'b1;
    if(count==1) begin busy<=0;done<=1;end
   end
   default:phase<=0;
  endcase
 end
end
endmodule
