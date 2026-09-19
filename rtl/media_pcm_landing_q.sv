// Restart-from-zero landing stage for standalone PCM streams.  It consumes
// decoded samples at full core speed until the requested 1/360000-second
// position, then reconnects the decoder to the real-time audio sink.
module media_pcm_landing_q #(
 parameter WIDTH=32
)(
 input wire clk,reset,input wire [1:0] rate_code,input wire [34:0] target_q,
 input wire input_valid,input wire input_eof,input wire [WIDTH-1:0] input_pcm,
 output wire input_ready,output wire output_valid,output wire output_eof,
 output wire [WIDTH-1:0] output_pcm,input wire output_ready,
 output reg landed=0
);
 reg [34:0] cursor_q=0;
 reg [5:0] fraction=0;
 wire [5:0] increment = rate_code == 2'd1 ? 6'd7 : rate_code == 2'd2 ? 6'd11 : 6'd8;
 wire [5:0] fraction_add = rate_code == 2'd0 ? 6'd8 : 6'd1;
 wire [5:0] modulus = rate_code == 2'd0 ? 6'd49 : rate_code == 2'd1 ? 6'd2 : 6'd4;
 wire discard=cursor_q<target_q;
 wire [6:0] fraction_next={1'b0,fraction}+{1'b0,fraction_add};
 wire accepted=input_valid&&input_ready&&!input_eof;
 assign input_ready=!reset&&(discard||output_ready);
 assign output_valid=!reset&&input_valid&&(!discard||input_eof);
 assign output_eof=input_eof;
 assign output_pcm=input_pcm;
 always @(posedge clk)begin
  if(reset)begin cursor_q<=0;fraction<=0;landed<=target_q==0;end
  else if(accepted)begin
   cursor_q<=cursor_q+increment+(fraction_next>=modulus);
   fraction<=fraction_next>=modulus?fraction_next-modulus:fraction_next[5:0];
   if(cursor_q+increment+(fraction_next>=modulus)>=target_q)landed<=1;
  end
 end
endmodule
