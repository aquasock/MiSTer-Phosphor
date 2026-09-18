// Shared LSB-first reservoir for Vorbis audio packets. The three header
// packets pass through without buffering. Audio packets cannot overlap: the
// consumer explicitly finishes each packet after decoding its padding.
module vorbis_packet_bits(
 input wire clk,input wire reset,
 input wire packet_valid,input wire [7:0] packet_data,
 input wire packet_start,input wire packet_end,output wire packet_ready,
 output reg audio_packet_start=0,
 output wire bits_valid,output wire [31:0] bits,output wire [6:0] bits_available,
 input wire consume_valid,input wire [5:0] consume_count,
 output reg packet_buffered_end=0,input wire finish_packet,
 output reg error=0
);
 reg [1:0] packet_number=0;
 reg audio_active=0;
 reg discarding=0;
 reg [63:0] reservoir=0;
 reg [6:0] bit_count=0;
 reg [2:0] error_reason=0;
 wire audio_target=packet_number==3;
 wire [6:0] drop_count=consume_valid?((packet_buffered_end&&consume_count>bit_count)?bit_count:consume_count):0;
 wire can_consume=!consume_valid||consume_count<=bit_count||packet_buffered_end;
 wire can_take_audio=discarding||(!packet_buffered_end&&bit_count-drop_count<=56);
 assign packet_ready=!audio_target?1'b1:(audio_active?can_take_audio:1'b1);
 wire take=packet_valid&&packet_ready;
 assign bits=reservoir[31:0];
 assign bits_available=bit_count;
 assign bits_valid=bit_count!=0;

 always @(posedge clk)begin
  if(reset)begin
   packet_number<=0;audio_active<=0;discarding<=0;reservoir<=0;bit_count<=0;
   audio_packet_start<=0;packet_buffered_end<=0;error<=0;error_reason<=0;
  end else begin
   audio_packet_start<=0;
   if(consume_valid&&!can_consume)begin error<=1;error_reason<=1;end
   if(finish_packet)begin
    if(!audio_active)begin error<=1;error_reason<=2;end
    else if(packet_buffered_end)begin audio_active<=0;packet_buffered_end<=0;end
    else discarding<=1;
    reservoir<=0;bit_count<=0;
   end else if(discarding)begin
    reservoir<=0;bit_count<=0;
    if(take&&packet_end)begin audio_active<=0;discarding<=0;packet_buffered_end<=0;end
   end else if(audio_active)begin
    if(consume_valid&&can_consume)begin reservoir<=reservoir>>drop_count;bit_count<=bit_count-drop_count;end
    if(take)begin
     if(packet_start)begin error<=1;error_reason<=3;end
     reservoir<=(reservoir>>drop_count)|({56'd0,packet_data}<<(bit_count-drop_count));
     bit_count<=bit_count-drop_count+8;
     if(packet_end)packet_buffered_end<=1;
    end
   end else if(take)begin
    if(audio_target)begin
     if(!packet_start)begin error<=1;error_reason<=4;end
     audio_active<=1;audio_packet_start<=1;reservoir<={56'd0,packet_data};bit_count<=8;
     packet_buffered_end<=packet_end;
    end
    if(packet_end&&packet_number<3)packet_number<=packet_number+1'b1;
   end
  end
 end
endmodule
