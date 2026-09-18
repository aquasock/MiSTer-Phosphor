// Streaming Ogg page/lacing parser. Reassembles packets without buffering
// packet payloads; backpressure propagates directly to the file reader.
module ogg_packet_reader(
 input wire clk,input wire reset,
 input wire byte_valid,input wire [7:0] byte_data,output wire byte_ready,
 output reg packet_valid=0,output reg [7:0] packet_data=0,
 output reg packet_start=0,output reg packet_end=0,input wire packet_ready,
 output reg [63:0] granule_position=0,output reg error=0
);
 localparam SYNC=0,HEADER=1,LACES=2,SEGMENT=3,BODY=4;
 reg [2:0] state=SYNC;
 reg [2:0] sync_count=0;
 reg [4:0] header_index=0;
 reg [7:0] header_type=0,page_segments=0,lace_count=0,lace_index=0;
 reg [7:0] segment_remaining=0,current_lace=0;
 reg packet_open=0;
 reg [31:0] serial=0,locked_serial=0,page_sequence=0,expected_sequence=0;
 reg serial_locked=0;
 (* ramstyle="MLAB" *) reg [7:0] laces[0:254];
 // Use a non-fall-through output register. This costs one fabric cycle per
 // payload byte but avoids advancing packet/page state on the same edge that
 // a previously registered byte is accepted after arbitrary backpressure.
 wire output_free=!packet_valid;
 // Do not advance into the following page header/lacing table while a payload
 // byte is stalled at the output. Otherwise long downstream backpressure can
 // desynchronize physical page parsing from the packet stream.
 assign byte_ready=state==SEGMENT?1'b0:output_free;
 wire take=byte_valid&&byte_ready;
 wire zero_terminates_255=current_lace==255&&lace_index+1'b1<page_segments&&laces[lace_index+1'b1]==0;
 wire body_packet_end=segment_remaining==1&&(current_lace<255||zero_terminates_255);

 always @(posedge clk)begin
  if(reset)begin
   state<=SYNC;sync_count<=0;header_index<=0;packet_valid<=0;packet_start<=0;packet_end<=0;
   packet_open<=0;serial_locked<=0;expected_sequence<=0;error<=0;granule_position<=0;
  end else begin
   if(packet_valid&&packet_ready)begin packet_valid<=0;packet_start<=0;packet_end<=0;end
   if(take)case(state)
    SYNC:begin
     // Sliding capture search recovers at the next physical page after damage.
     if((sync_count==0&&byte_data=="O")||(sync_count==1&&byte_data=="g")||
        (sync_count==2&&byte_data=="g")||(sync_count==3&&byte_data=="S"))begin
      if(sync_count==3)begin state<=HEADER;header_index<=4;sync_count<=0;end
      else sync_count<=sync_count+1'b1;
     // A partial capture match can occur while resynchronizing after a
     // backpressured page boundary. Keep the sliding search non-destructive;
     // structural header, serial and sequence failures remain sticky errors.
     end else sync_count<=byte_data=="O"?1:0;
    end
    HEADER:begin
     case(header_index)
      4:if(byte_data!=0)begin error<=1;state<=SYNC;end
      5:header_type<=byte_data;
      6:granule_position[7:0]<=byte_data;7:granule_position[15:8]<=byte_data;
      8:granule_position[23:16]<=byte_data;9:granule_position[31:24]<=byte_data;
      10:granule_position[39:32]<=byte_data;11:granule_position[47:40]<=byte_data;
      12:granule_position[55:48]<=byte_data;13:granule_position[63:56]<=byte_data;
      14:serial[7:0]<=byte_data;15:serial[15:8]<=byte_data;
      16:serial[23:16]<=byte_data;17:serial[31:24]<=byte_data;
      18:page_sequence[7:0]<=byte_data;19:page_sequence[15:8]<=byte_data;
      20:page_sequence[23:16]<=byte_data;21:page_sequence[31:24]<=byte_data;
      26:begin
       page_segments<=byte_data;lace_count<=0;
       if(serial_locked&&serial!=locked_serial)error<=1;
       else if(serial_locked&&page_sequence!=expected_sequence)error<=1;
       else begin
        if(!serial_locked)begin serial_locked<=1;locked_serial<=serial;end
        expected_sequence<=page_sequence+1'b1;
       end
       if(header_type[0]!=packet_open)begin error<=1;packet_open<=header_type[0];end
       state<=byte_data==0?SYNC:LACES;
      end
     endcase
     if(header_index!=26)header_index<=header_index+1'b1;
    end
    LACES:begin
     laces[lace_count]<=byte_data;lace_count<=lace_count+1'b1;
     if(lace_count+1'b1==page_segments)begin lace_index<=0;state<=SEGMENT;end
    end
    SEGMENT:;
    BODY:begin
     packet_valid<=1;packet_data<=byte_data;packet_start<=!packet_open;
     // A zero lace after a full 255-byte segment terminates that same packet;
     // mark the preceding data byte because the zero segment emits no byte.
     packet_end<=body_packet_end;
     packet_open<=!body_packet_end;
     if(segment_remaining==1)begin
      if(lace_index+1'b1==page_segments)state<=SYNC;
      else begin lace_index<=lace_index+1'b1;state<=SEGMENT;end
     end else segment_remaining<=segment_remaining-1'b1;
    end
   endcase
   // Lacing RAM is asynchronous here so SEGMENT can be a zero-input setup
   // cycle; this also handles a continuously asserted upstream valid cleanly.
   if(state==SEGMENT)begin
    current_lace<=laces[lace_index];segment_remaining<=laces[lace_index];
    if(laces[lace_index]==0)begin
     packet_open<=0;
     if(lace_index+1'b1==page_segments)state<=SYNC;
     else begin lace_index<=lace_index+1'b1;state<=SEGMENT;end
    end else state<=BODY;
   end
  end
 end
endmodule
