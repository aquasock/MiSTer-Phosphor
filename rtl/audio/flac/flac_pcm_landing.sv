// Discard decoded preroll without putting it on the native audio clock.
// CRC admission remains upstream in flac_frame_store.
module flac_pcm_landing(
 input wire clk,reset,
 input wire [35:0] start_sample,target_sample,
 input wire input_valid,input_eof,
 input wire [31:0] input_pcm,
 output wire input_ready,
 output wire output_valid,output_eof,
 output wire [31:0] output_pcm,
 input wire output_ready,
 output reg landed=0
);
 reg [35:0] cursor=0;
 wire discard=cursor<target_sample;
 assign input_ready=!reset&&(discard||output_ready);
 assign output_valid=!reset&&input_valid&&(!discard||input_eof);
 assign output_eof=input_eof;
 assign output_pcm=input_pcm;
 always @(posedge clk)begin
  if(reset)begin cursor<=start_sample;landed<=0;end
  else if(input_valid&&!input_eof)begin
   if(input_ready)cursor<=cursor+1'b1;
   if(!discard)landed<=1;
  end
 end
endmodule
