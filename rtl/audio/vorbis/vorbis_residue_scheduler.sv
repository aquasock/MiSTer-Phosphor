// Residue classification/pass scheduler. It decodes classwords once during
// pass zero, expands them in base `classifications`, and emits the vector-book
// work required by each cascade bit on passes 0..7.
module vorbis_residue_scheduler(
 input wire clk,input wire reset,input wire start,
 input wire [23:0] residue_begin,input wire [23:0] residue_end,input wire [23:0] partition_size,
 input wire [6:0] classifications,input wire [7:0] classbook,input wire [7:0] classbook_dimensions,
 output reg [5:0] class_query=0,input wire [7:0] class_cascade,
 output reg [2:0] pass_query=0,input wire [7:0] pass_book,
 output reg huffman_valid=0,input wire huffman_ready,output reg [7:0] huffman_book=0,
 input wire symbol_valid,input wire [17:0] symbol,
 output reg task_valid=0,input wire task_ready,output reg [7:0] task_book=0,
 output reg [2:0] task_pass=0,output reg [6:0] task_partition=0,
 output reg [23:0] task_offset=0,output reg [23:0] task_length=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,PARTITION=1,CLASS_REQ=2,CLASS_WAIT=3,DECOMPOSE=4,
  SELECT=5,TASK=6,NEXT_PART=7,NEXT_PASS=8,FINISH=9,SELECT_WAIT=10,
  COUNT_DIV_START=11,COUNT_DIV_WAIT=12,DECOMP_DIV_START=13,DECOMP_DIV_WAIT=14;
 reg [3:0] state=IDLE;
 reg [6:0] partitions=0,partition_index=0,group_start=0;
 reg [7:0] dimension_index=0;
 reg [7:0] group_position=0;
 reg [17:0] classword=0;
 reg [5:0] partition_class[0:63];
 reg [23:0] divider_numerator=0,divider_denominator=1;
 wire divider_ready,divider_done,divider_error;wire [23:0] divider_quotient,divider_remainder;
 vorbis_unsigned_divider #(.WIDTH(24)) scheduler_divider(.clk(clk),.reset(reset),
  .start(state==COUNT_DIV_START||state==DECOMP_DIV_START),.numerator(divider_numerator),
  .denominator(divider_denominator),.ready(divider_ready),.done(divider_done),.error(divider_error),
  .quotient(divider_quotient),.remainder(divider_remainder));
 assign ready=state==IDLE;
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;huffman_valid<=0;task_valid<=0;done<=0;error<=0;end
  else begin
   done<=0;
   if(huffman_valid&&huffman_ready)huffman_valid<=0;
   if(task_valid&&task_ready)task_valid<=0;
   case(state)
    IDLE:if(start)begin
     if(partition_size==0||classifications==0||classbook_dimensions==0||classbook_dimensions>64||residue_end<residue_begin)
     begin error<=1;state<=FINISH;end
     else begin
      divider_numerator<=residue_end-residue_begin;divider_denominator<=partition_size;
      partition_index<=0;group_position<=0;pass_query<=0;state<=COUNT_DIV_START;
     end
    end
    COUNT_DIV_START:if(divider_ready)state<=COUNT_DIV_WAIT;
    COUNT_DIV_WAIT:if(divider_done)begin
     if(divider_error||divider_quotient>64)begin error<=1;state<=FINISH;end
     else begin partitions<=divider_quotient[6:0];state<=PARTITION;end
    end
    PARTITION:begin
     if(partition_index>=partitions)state<=NEXT_PASS;
     else if(pass_query==0&&group_position==0)begin
      group_start<=partition_index;huffman_book<=classbook;huffman_valid<=1;state<=CLASS_REQ;
     end else begin class_query<=partition_class[partition_index];state<=SELECT_WAIT;end
    end
    CLASS_REQ:if(huffman_valid&&huffman_ready)state<=CLASS_WAIT;
    CLASS_WAIT:if(symbol_valid)begin classword<=symbol;dimension_index<=classbook_dimensions;state<=DECOMPOSE;end
    DECOMPOSE:begin
     divider_numerator<={6'd0,classword};divider_denominator<={17'd0,classifications};state<=DECOMP_DIV_START;
    end
    DECOMP_DIV_START:if(divider_ready)state<=DECOMP_DIV_WAIT;
    DECOMP_DIV_WAIT:if(divider_done)begin
     if(divider_error)begin error<=1;state<=FINISH;end
     else begin
      dimension_index<=dimension_index-1'b1;
      if(group_start+dimension_index-1'b1<partitions)
       partition_class[group_start+dimension_index-1'b1]<=divider_remainder[5:0];
      classword<=divider_quotient[17:0];
      if(dimension_index==1)begin class_query<=divider_remainder[5:0];state<=SELECT_WAIT;end
      else state<=DECOMPOSE;
     end
    end
    SELECT_WAIT:state<=SELECT;
    SELECT:begin
     if(class_cascade[pass_query])begin
      if(pass_book==8'hff)begin error<=1;state<=NEXT_PART;end
      else begin
       task_book<=pass_book;task_pass<=pass_query;task_partition<=partition_index;
       task_offset<=residue_begin+partition_index*partition_size;task_length<=partition_size;
       task_valid<=1;state<=TASK;
      end
     end else state<=NEXT_PART;
    end
    TASK:if(task_valid&&task_ready)state<=NEXT_PART;
    NEXT_PART:begin
     partition_index<=partition_index+1'b1;
     if(pass_query==0)begin
      if(group_position+1'b1>=classbook_dimensions)group_position<=0;
      else group_position<=group_position+1'b1;
     end
     state<=PARTITION;
    end
    NEXT_PASS:begin
     if(pass_query==7)state<=FINISH;
     else begin pass_query<=pass_query+1'b1;partition_index<=0;group_position<=0;state<=PARTITION;end
    end
    FINISH:begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
