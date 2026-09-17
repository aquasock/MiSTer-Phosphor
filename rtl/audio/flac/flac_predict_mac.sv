// Serial FLAC prediction primitive. Taps arrive newest history first.
// 17-bit history preserves the stereo side channel; 40-bit accumulation
// covers 32 products of signed 17-bit samples and signed 16-bit coefficients.
// Parser owns history RAM, coefficient precision and residual syntax checks.
module flac_predict_mac (
 input wire clk, reset,
 input wire start,
 input wire [5:0] order,
 input wire [3:0] shift,
 input wire signed [31:0] residual,
 input wire side_channel,
 input wire tap_valid,
 output wire tap_ready,
 input wire signed [16:0] history,
 input wire signed [15:0] coefficient,
 output wire busy,
 output reg result_valid,
 input wire result_ready,
 output reg signed [16:0] result,
 output reg error
);
 localparam IDLE=2'd0, TAPS=2'd1, FINISH=2'd2, OUTPUT=2'd3;
 reg [1:0] state;
 reg [5:0] remaining;
 reg [3:0] shift_q;
 reg side_q;
 reg signed [31:0] residual_q;
 reg signed [39:0] accumulator;
 wire signed [32:0] product = history * coefficient;
 wire signed [39:0] extended_product = {{7{product[32]}},product};
 wire signed [39:0] extended_residual = {{8{residual_q[31]}},residual_q};
 wire signed [39:0] reconstructed = (accumulator >>> shift_q) + extended_residual;
 wire fits_side = reconstructed[39:16] == {24{reconstructed[16]}};
 wire fits_normal = reconstructed[39:15] == {25{reconstructed[15]}};
 assign busy = state != IDLE;
 assign tap_ready = state == TAPS;
 always @(posedge clk) begin
  if(reset) begin
   state<=IDLE;remaining<=0;shift_q<=0;side_q<=0;residual_q<=0;
   accumulator<=0;result_valid<=0;result<=0;error<=0;
  end else begin
   case(state)
    IDLE: if(start) begin
     accumulator<=0;remaining<=order;shift_q<=shift;side_q<=side_channel;
     residual_q<=residual;error<=0;
     if(order>32) begin result<=0;error<=1;result_valid<=1;state<=OUTPUT;end
     else state<=order==0 ? FINISH:TAPS;
    end
    TAPS: if(tap_valid) begin
     accumulator<=accumulator+extended_product;
     remaining<=remaining-1'b1;
     if(remaining==1) state<=FINISH;
    end
    FINISH: begin
     result<=reconstructed[16:0];
     error<=side_q ? !fits_side:!fits_normal;
     result_valid<=1;state<=OUTPUT;
    end
    OUTPUT: if(result_ready) begin result_valid<=0;state<=IDLE;end
   endcase
  end
 end
endmodule
