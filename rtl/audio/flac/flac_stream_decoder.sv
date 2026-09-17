// Native FLAC file framing for the project's 44100 Hz / 16-bit stereo profile.
// Coded channel samples go to a provisional frame store, never directly to PCM.
// The store owns CRC-admitted frames after commit_valid && commit_ready.
module flac_stream_decoder #(parameter ENABLE_RESUME=0) (
 input wire clk,reset,
 input wire resume_frame,
 input wire [35:0] resume_sample,resume_total,
 input wire [15:0] resume_min_block,resume_max_block,
 input wire [7:0] input_data,
 input wire input_valid,input_end,
 output wire input_ready,
 output reg metadata_valid,
 output reg [35:0] total_samples,
 output wire begin_valid,
 input wire begin_ready,
 output reg [15:0] frame_size,
 output reg [3:0] channel_assignment,
 output reg [35:0] frame_position,
 output wire sample_valid,
 input wire sample_ready,
 output reg sample_channel,
 output reg [15:0] sample_index,
 output wire signed [16:0] sample_data,
 output wire commit_valid,
 input wire commit_ready,store_error,
 output reg finished,
 output reg [3:0] error
);
 localparam MAGIC=0,GET=1,MAGIC_CHECK=2,META_HEADER=3,INFO_BLOCKS=4,
  SKIP=5,INFO_RATE=6,META_NEXT=7,WAIT_FRAME=8,SYNC=9,FORMAT=10,
  NUMBER_FIRST=11,NUMBER_MORE=12,NUMBER_CHECK=13,BLOCK_EXTRA=14,
  RATE_START=15,RATE_CHECK=16,HEADER_CRC=17,BEGIN_FRAME=18,
  START_SUB=19,SUB=20,PADDING=21,FRAME_CRC=22,COMMIT=23,FAILED=24;
 reg [4:0] state,return_state,skip_return;
 reg first_resume;
 reg [6:0] bits_left;
 reg [63:0] field;reg [62:0] accumulator;
 reg [7:0] byte_buffer;reg [3:0] byte_bits;
 reg [23:0] skip_left;
 reg seen_info,meta_last,crc_active,header_active;
 reg [15:0] min_block,max_block;
 reg [15:0] crc16;reg [7:0] crc8;
 reg [3:0] block_code,rate_code;
 reg variable_block,blocking_known,blocking_mode,short_frame;
 reg [15:0] fixed_size;
 reg [35:0] frame_number,coded_number,number_min;
 reg [2:0] continuation;
 wire sf_ready,sf_valid,sf_done,sf_error;
 wire [4:0] sf_bits=((channel_assignment==8||channel_assignment==10)&&sample_channel)||
                   (channel_assignment==9&&!sample_channel)?5'd17:5'd16;
 flac_subframe subframe(.clk(clk),.reset(reset||state==FAILED),.start(state==START_SUB),
  .block_size(frame_size),.channel_bits(sf_bits),
  .bit_valid(state==SUB&&byte_bits!=0),.bit_data(byte_buffer[7]),
  .bit_end(input_end&&!input_valid&&byte_bits==0),.bit_ready(sf_ready),
  .sample_valid(sf_valid),.sample_ready(state==SUB&&sample_ready),.sample_data(sample_data),
  .done(sf_done),.error(sf_error));
 wire demand=state==GET||(state==SUB&&sf_ready);
 wire consume_bit=byte_bits!=0&&demand;
 assign input_ready=!reset&&!store_error&&error==0&&((demand&&byte_bits==0)||state==SKIP);
 assign sample_valid=state==SUB&&sf_valid&&!reset&&!store_error&&error==0;
 assign begin_valid=state==BEGIN_FRAME&&!reset&&!store_error&&error==0;
 assign commit_valid=state==COMMIT&&!reset&&!store_error&&error==0;
 function automatic [7:0] next_crc8(input[7:0] old,input[7:0] b);
  reg[7:0] c;integer i;begin c=old^b;for(i=0;i<8;i=i+1)c=c[7]?(c<<1)^8'h07:c<<1;next_crc8=c;end
 endfunction
 function automatic [15:0] next_crc16(input[15:0] old,input[7:0] b);
  reg[15:0] c;integer i;begin c=old^{b,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h8005:c<<1;next_crc16=c;end
 endfunction
 task automatic read_bits(input[6:0] n,input[4:0] next_state);
  begin bits_left<=n;accumulator<=0;return_state<=next_state;
   if(n==0)begin field<=0;state<=next_state;end else state<=GET;
  end
 endtask
 task automatic skip_bytes(input[23:0] n,input[4:0] next_state);
  begin skip_left<=n;skip_return<=next_state;state<=n==0?next_state:SKIP;end
 endtask
 task automatic fail(input[3:0] code);begin error<=code;state<=FAILED;end endtask
 wire[7:0] nb=field[7:0];
 wire[36:0] next_position={1'b0,frame_position}+{21'd0,frame_size};
 always @(posedge clk)begin
  if(reset)begin
   state<=(ENABLE_RESUME&&resume_frame)?WAIT_FRAME:MAGIC;first_resume<=ENABLE_RESUME&&resume_frame;return_state<=MAGIC;skip_return<=MAGIC;bits_left<=0;field<=0;accumulator<=0;
   byte_buffer<=0;byte_bits<=0;skip_left<=0;seen_info<=0;meta_last<=0;
   crc_active<=0;header_active<=0;min_block<=(ENABLE_RESUME&&resume_frame)?resume_min_block:16'd0;max_block<=(ENABLE_RESUME&&resume_frame)?resume_max_block:16'd0;crc16<=0;crc8<=0;
   block_code<=0;rate_code<=0;variable_block<=0;blocking_known<=0;blocking_mode<=0;
   short_frame<=0;fixed_size<=0;frame_number<=0;coded_number<=0;number_min<=0;continuation<=0;
   metadata_valid<=ENABLE_RESUME&&resume_frame;total_samples<=(ENABLE_RESUME&&resume_frame)?resume_total:36'd0;frame_size<=0;channel_assignment<=0;frame_position<=(ENABLE_RESUME&&resume_frame)?resume_sample:36'd0;
   sample_channel<=0;sample_index<=0;finished<=0;error<=0;
  end else if(store_error)fail(8);
  else begin
   if(input_valid&&input_ready&&state!=SKIP)begin
    byte_buffer<=input_data;byte_bits<=8;
    if(crc_active)crc16<=next_crc16(crc16,input_data);
    if(header_active)crc8<=next_crc8(crc8,input_data);
   end else if(consume_bit)begin byte_buffer<={byte_buffer[6:0],1'b0};byte_bits<=byte_bits-1'b1;end
   case(state)
    MAGIC:read_bits(32,MAGIC_CHECK);
    GET:if(consume_bit)begin
     accumulator<={accumulator[61:0],byte_buffer[7]};bits_left<=bits_left-1'b1;
     if(bits_left==1)begin field<={accumulator,byte_buffer[7]};state<=return_state;end
    end else if(input_end&&!input_valid&&byte_bits==0)fail(6);
    MAGIC_CHECK:if(field!=64'h664c6143)fail(1);else read_bits(32,META_HEADER);
    META_HEADER:begin
     meta_last<=field[31];
     if(field[30:24]==127)fail(2);
     else if(!seen_info)begin
      if(field[30:24]!=0||field[23:0]!=34)fail(2);
      else begin seen_info<=1;read_bits(32,INFO_BLOCKS);end
     end else if(field[30:24]==0)fail(2);
     else skip_bytes(field[23:0],META_NEXT);
    end
    INFO_BLOCKS:if(field[31:16]<16||field[15:0]<field[31:16])fail(2);
     else begin min_block<=field[31:16];max_block<=field[15:0];skip_bytes(6,INFO_RATE);end
    INFO_RATE:read_bits(64,META_NEXT);
    META_NEXT:if(!metadata_valid)begin
     if(field[63:44]!=44100||field[43:41]!=1||field[40:36]!=15)fail(2);
     else begin total_samples<=field[35:0];metadata_valid<=1;skip_bytes(16,META_NEXT);end
    end else if(meta_last)state<=WAIT_FRAME;else read_bits(32,META_HEADER);
    SKIP:if(input_valid)begin
     skip_left<=skip_left-1'b1;if(skip_left==1)state<=skip_return;
    end else if(input_end)fail(6);
    WAIT_FRAME:begin
     crc_active<=0;header_active<=0;
     if(input_valid)begin
      if(short_frame)fail(7);
      else begin crc_active<=1;header_active<=1;crc8<=0;crc16<=0;read_bits(16,SYNC);end
     end else if(input_end)begin
      if(total_samples!=0&&frame_position!=total_samples)fail(6);
      else finished<=1;
     end
    end
    SYNC:if(field[15:1]!=15'h7ffc)fail(3);
     else begin variable_block<=field[0];read_bits(16,FORMAT);end
    FORMAT:begin
     block_code<=field[15:12];rate_code<=field[11:8];channel_assignment<=field[7:4];
     if(field[0]||!(field[3:1]==0||field[3:1]==4)||
        !(field[7:4]==1||field[7:4]==8||field[7:4]==9||field[7:4]==10)||field[15:12]==0||
        !(field[11:8]==0||field[11:8]==9||field[11:8]==12||field[11:8]==13||field[11:8]==14))fail(3);
     else begin
      if(field[15:12]==1)frame_size<=192;
      else if(field[15:12]<=5)frame_size<=16'd576<<(field[15:12]-2);
      else if(field[15:12]>=8)frame_size<=16'd256<<(field[15:12]-8);
      read_bits(8,NUMBER_FIRST);
     end
    end
    NUMBER_FIRST:begin
     if(!nb[7])begin coded_number<={29'd0,nb[6:0]};number_min<=0;continuation<=0;state<=NUMBER_CHECK;end
     else if(nb[7:5]==3'b110)begin coded_number<={31'd0,nb[4:0]};number_min<=128;continuation<=1;read_bits(8,NUMBER_MORE);end
     else if(nb[7:4]==4'b1110)begin coded_number<={32'd0,nb[3:0]};number_min<=2048;continuation<=2;read_bits(8,NUMBER_MORE);end
     else if(nb[7:3]==5'b11110)begin coded_number<={33'd0,nb[2:0]};number_min<=65536;continuation<=3;read_bits(8,NUMBER_MORE);end
     else if(nb[7:2]==6'b111110)begin coded_number<={34'd0,nb[1:0]};number_min<=2097152;continuation<=4;read_bits(8,NUMBER_MORE);end
     else if(nb[7:1]==7'b1111110)begin coded_number<={35'd0,nb[0]};number_min<=67108864;continuation<=5;read_bits(8,NUMBER_MORE);end
     else if(nb==254)begin coded_number<=0;number_min<=36'h080000000;continuation<=6;read_bits(8,NUMBER_MORE);end
     else fail(3);
    end
    NUMBER_MORE:if(nb[7:6]!=2'b10)fail(3);else begin
     coded_number<={coded_number[29:0],nb[5:0]};continuation<=continuation-1'b1;
     if(continuation==1)state<=NUMBER_CHECK;else read_bits(8,NUMBER_MORE);
    end
    NUMBER_CHECK:begin
     if(first_resume&&!variable_block)frame_number<=coded_number;
     if(coded_number<number_min||(!variable_block&&coded_number[35:28]!=0)||
      (variable_block?coded_number!=frame_position:(!first_resume&&coded_number!=frame_number))||
      (blocking_known&&variable_block!=blocking_mode))fail(7);
     else if(block_code==6)read_bits(8,BLOCK_EXTRA);
     else if(block_code==7)read_bits(16,BLOCK_EXTRA);
     else state<=RATE_START;
    end
    BLOCK_EXTRA:if(field[15:0]==65535)fail(3);else begin frame_size<=field[15:0]+1'b1;state<=RATE_START;end
    RATE_START:begin
     if(frame_size==0||frame_size>max_block||(!variable_block&&blocking_known&&frame_size>fixed_size))fail(3);
     else if(rate_code>=12)read_bits(rate_code==12?7'd8:7'd16,RATE_CHECK);
     else read_bits(8,HEADER_CRC);
    end
    RATE_CHECK:if(!((rate_code==13&&field==44100)||(rate_code==14&&field==4410)))fail(3);else read_bits(8,HEADER_CRC);
    HEADER_CRC:if(crc8!=0)fail(4);else begin
     header_active<=0;first_resume<=0;sample_channel<=0;sample_index<=0;state<=BEGIN_FRAME;
     short_frame<=frame_size<min_block||(!variable_block&&blocking_known&&frame_size!=fixed_size);
     if(!blocking_known)begin blocking_known<=1;blocking_mode<=variable_block;fixed_size<=frame_size;end
    end
    BEGIN_FRAME:if(begin_ready)state<=START_SUB;
    START_SUB:state<=SUB;
    SUB:begin
     if(sample_valid&&sample_ready)sample_index<=sample_index+1'b1;
     if(sf_error)fail(5);
     else if(sf_done)begin
      if(!sample_channel)begin sample_channel<=1;sample_index<=0;state<=START_SUB;end
      else if(byte_bits!=0)read_bits({3'd0,byte_bits},PADDING);
      else read_bits(16,FRAME_CRC);
     end
    end
    PADDING:if(field!=0)fail(3);else read_bits(16,FRAME_CRC);
    FRAME_CRC:if(crc16!=0)fail(4);
     else if(next_position[36]||(total_samples!=0&&next_position>{1'b0,total_samples}))fail(7);
     else state<=COMMIT;
    COMMIT:if(commit_ready)begin frame_position<=next_position[35:0];frame_number<=frame_number+1'b1;state<=WAIT_FRAME;end
    FAILED:state<=FAILED;
    default:fail(3);
   endcase
  end
 end
endmodule
