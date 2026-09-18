// Floor-1 packet unpack and Y-value reconstruction. Huffman decoding is
// requested by codebook number so the prefix/fallback engine can be shared
// with residue decoding.
module vorbis_floor1_unpack(
 input wire clk,input wire reset,input wire start,input wire [5:0] floor_number,
 output reg [5:0] floor_query,output reg [4:0] floor_part_query,
 output reg [3:0] floor_class_query,output reg [2:0] floor_subbook_query,
 output reg [6:0] floor_x_query,
 input wire [15:0] floor_query_type,input wire [4:0] floor_query_partitions,
 input wire [3:0] floor_query_partition_class,input wire [3:0] floor_query_class_dimensions,
 input wire [2:0] floor_query_class_subclasses,input wire [7:0] floor_query_class_masterbook,
 input wire [7:0] floor_query_subbook,input wire [2:0] floor_query_multiplier,
 input wire [3:0] floor_query_rangebits,input wire [15:0] floor_query_x,
 input wire bits_valid,input wire [31:0] bits,input wire [6:0] bits_available,
 output reg consume_valid=0,output reg [5:0] consume_count=0,
 output reg huffman_valid=0,input wire huffman_ready,output reg [7:0] huffman_book=0,
 input wire symbol_valid,input wire [17:0] symbol,
 output wire ready,output reg done=0,output reg present=0,output reg error=0,
 output reg point_valid=0,input wire point_ready,output reg [6:0] point_index=0,
 output reg [15:0] point_x=0,output reg [8:0] point_y=0,output reg point_active=0
);
 localparam IDLE=0,PRESENCE=1,Y0=2,Y1=3,PART=4,MASTER_REQ=5,MASTER_WAIT=6,
  VALUE_SELECT=7,VALUE_REQ=8,VALUE_WAIT=9,RECON_INIT=10,RECON_SCAN=11,
  RECON_CALC=12,OUTPUT=13,FINISH=14,BIT_GAP=15,CONFIG_WAIT=16,CLASS_WAIT=17,
  CLASS_USE=18,VALUE_QUERY_WAIT=19,RECON_TARGET_WAIT=20,RECON_SCAN_INIT=21,
  RECON_SCAN_WAIT=22,OUTPUT_WAIT=23,PART_WAIT=24,RECON_DIV_START=25,
  RECON_DIV_WAIT=26,RECON_UNWRAP=27;
 reg [4:0] state=IDLE;
 reg [4:0] resume_state=IDLE;
 reg [8:0] range=0;
 reg [5:0] y_bits=0;
 reg [4:0] partition_index=0;
 reg [3:0] current_class=0,current_dimension=0;
 reg [2:0] subclass_bits=0;
 reg [17:0] classword=0;
 reg [6:0] values=0,recon_index=0,scan_index=0,low_index=0,high_index=0,output_index=0;
 reg [15:0] recon_x=0,low_x=0,high_x=0;
 reg [8:0] raw_y[0:64];
 reg [8:0] final_y[0:64];
 reg active_y[0:64];
 integer predicted,highroom,lowroom,room,unwrapped;
 reg [24:0] interpolation_numerator=0,interpolation_denominator=1;
 reg [8:0] interpolation_base=0;reg interpolation_negative=0;
 wire interpolation_divider_ready,interpolation_divider_done,interpolation_divider_error;
 wire [24:0] interpolation_quotient,interpolation_remainder;

 function [5:0] ilog9;input [8:0] value;integer i;begin
  ilog9=0;for(i=0;i<9;i=i+1)if(value[i])ilog9=i+1;
 end endfunction
 vorbis_unsigned_divider #(.WIDTH(25)) interpolation_divider(.clk(clk),.reset(reset),
  .start(state==RECON_DIV_START),.numerator(interpolation_numerator),
  .denominator(interpolation_denominator),.ready(interpolation_divider_ready),
  .done(interpolation_divider_done),.error(interpolation_divider_error),
  .quotient(interpolation_quotient),.remainder(interpolation_remainder));
 wire [31:0] bit_mask=y_bits==32?32'hffffffff:((32'd1<<y_bits)-1'b1);
 assign ready=state==IDLE;

 always @(posedge clk)begin
  if(reset)begin state<=IDLE;done<=0;present<=0;error<=0;consume_valid<=0;huffman_valid<=0;point_valid<=0;end
  else begin
   consume_valid<=0;done<=0;
   if(huffman_valid&&huffman_ready)huffman_valid<=0;
   if(point_valid&&point_ready)point_valid<=0;
   case(state)
    IDLE:if(start)begin
     floor_query<=floor_number;floor_part_query<=0;floor_class_query<=0;floor_subbook_query<=0;floor_x_query<=0;
     present<=0;error<=0;values<=2;state<=CONFIG_WAIT;
    end
    CONFIG_WAIT:state<=PRESENCE;
    PRESENCE:if(bits_valid&&bits_available>=1)begin
     consume_valid<=1;consume_count<=1;
     if(!bits[0])begin present<=0;resume_state<=FINISH;state<=BIT_GAP;end
     else if(floor_query_type!=1)begin error<=1;resume_state<=FINISH;state<=BIT_GAP;end
     else begin
      present<=1;
      case(floor_query_multiplier)1:range<=256;2:range<=128;3:range<=86;default:range<=64;endcase
      case(floor_query_multiplier)1:y_bits<=8;2:y_bits<=7;3:y_bits<=7;default:y_bits<=6;endcase
      resume_state<=Y0;state<=BIT_GAP;
     end
    end
    Y0:if(bits_valid&&bits_available>=y_bits)begin
     raw_y[0]<=bits&bit_mask;final_y[0]<=bits&bit_mask;active_y[0]<=1;
     consume_valid<=1;consume_count<=y_bits;resume_state<=Y1;state<=BIT_GAP;
    end
    Y1:if(bits_valid&&bits_available>=y_bits)begin
     raw_y[1]<=bits&bit_mask;final_y[1]<=bits&bit_mask;active_y[1]<=1;
     consume_valid<=1;consume_count<=y_bits;partition_index<=0;resume_state<=PART;state<=BIT_GAP;
    end
    PART:begin
     if(partition_index==floor_query_partitions)begin recon_index<=2;state<=RECON_INIT;end
     else begin
      current_class<=floor_query_partition_class;floor_class_query<=floor_query_partition_class;
      current_dimension<=0;state<=CLASS_WAIT;
     end
    end
    CLASS_WAIT:state<=CLASS_USE;
    CLASS_USE:begin
      subclass_bits<=floor_query_class_subclasses;
      if(floor_query_class_subclasses==0)begin classword<=0;state<=VALUE_SELECT;end
      else begin huffman_book<=floor_query_class_masterbook;huffman_valid<=1;state<=MASTER_REQ;end
    end
    MASTER_REQ:if(huffman_valid&&huffman_ready)state<=MASTER_WAIT;
    MASTER_WAIT:if(symbol_valid)begin classword<=symbol;state<=VALUE_SELECT;end
    VALUE_SELECT:begin
     floor_subbook_query<=classword&((1<<subclass_bits)-1'b1);
     if(subclass_bits!=0)classword<=classword>>subclass_bits;
     state<=VALUE_QUERY_WAIT;
    end
    VALUE_QUERY_WAIT:state<=VALUE_REQ;
    VALUE_REQ:begin
     if(floor_query_subbook==8'hff)begin raw_y[values]<=0;values<=values+1'b1;state<=VALUE_WAIT;end
     else begin huffman_book<=floor_query_subbook;huffman_valid<=1;state<=VALUE_WAIT;end
    end
    VALUE_WAIT:begin
     if(floor_query_subbook==8'hff||symbol_valid)begin
      if(floor_query_subbook!=8'hff)begin raw_y[values]<=symbol[8:0];values<=values+1'b1;end
      if(current_dimension+1'b1==floor_query_class_dimensions)begin
       partition_index<=partition_index+1'b1;floor_part_query<=partition_index+1'b1;state<=PART_WAIT;
      end else begin current_dimension<=current_dimension+1'b1;state<=VALUE_SELECT;end
     end
    end
    RECON_INIT:begin
     if(recon_index==values)begin output_index<=0;floor_x_query<=0;state<=OUTPUT_WAIT;end
     else begin floor_x_query<=recon_index;scan_index<=0;low_index<=0;high_index<=1;state<=RECON_TARGET_WAIT;end
    end
    RECON_TARGET_WAIT:state<=RECON_SCAN_INIT;
    RECON_SCAN_INIT:begin recon_x<=floor_query_x;floor_x_query<=0;low_x<=0;high_x<=0;scan_index<=1;state<=RECON_SCAN_WAIT;end
    RECON_SCAN_WAIT:state<=RECON_SCAN;
    RECON_SCAN:begin
      if(floor_query_x<recon_x&&floor_query_x>=low_x)begin low_x<=floor_query_x;low_index<=scan_index-1'b1;end
      if(floor_query_x>recon_x&&(high_x==0||floor_query_x<=high_x))begin high_x<=floor_query_x;high_index<=scan_index-1'b1;end
      if(scan_index==recon_index)state<=RECON_CALC;
      else begin floor_x_query<=scan_index;scan_index<=scan_index+1'b1;state<=RECON_SCAN_WAIT;end
    end
    RECON_CALC:begin
     interpolation_base<=final_y[low_index];
     interpolation_negative<=final_y[high_index]<final_y[low_index];
     interpolation_numerator<=(final_y[high_index]>=final_y[low_index]?
      final_y[high_index]-final_y[low_index]:final_y[low_index]-final_y[high_index])*(recon_x-low_x);
     interpolation_denominator<=high_x-low_x;state<=RECON_DIV_START;
    end
    RECON_DIV_START:if(interpolation_divider_ready)state<=RECON_DIV_WAIT;
    RECON_DIV_WAIT:if(interpolation_divider_done)begin
     if(interpolation_divider_error)begin error<=1;state<=FINISH;end
     else begin
      predicted<=interpolation_negative?interpolation_base-interpolation_quotient:
       interpolation_base+interpolation_quotient;
      state<=RECON_UNWRAP;
     end
    end
    RECON_UNWRAP:begin
     highroom=range-predicted;lowroom=predicted;room=2*(highroom<lowroom?highroom:lowroom);
     if(raw_y[recon_index]!=0)begin
      active_y[recon_index]<=1;
      active_y[low_index]<=1;active_y[high_index]<=1;
      if(raw_y[recon_index]>=room)
       unwrapped=highroom>lowroom?raw_y[recon_index]-lowroom+predicted:
        predicted-raw_y[recon_index]+highroom-1;
      else if(raw_y[recon_index]&1)unwrapped=predicted-((raw_y[recon_index]+1)>>1);
      else unwrapped=predicted+(raw_y[recon_index]>>1);
      final_y[recon_index]<=unwrapped;
     end else begin active_y[recon_index]<=0;final_y[recon_index]<=predicted;end
     recon_index<=recon_index+1'b1;state<=RECON_INIT;
    end
    OUTPUT:if(!point_valid)begin
     point_index<=output_index;point_x<=floor_query_x;point_y<=final_y[output_index];point_active<=active_y[output_index];point_valid<=1;
     if(output_index+1'b1==values)state<=FINISH;
     else begin output_index<=output_index+1'b1;floor_x_query<=output_index+1'b1;state<=OUTPUT_WAIT;end
    end
    OUTPUT_WAIT:state<=OUTPUT;
    PART_WAIT:state<=PART;
    FINISH:if(!point_valid)begin done<=1;state<=IDLE;end
    BIT_GAP:state<=resume_state;
   endcase
  end
 end
endmodule
