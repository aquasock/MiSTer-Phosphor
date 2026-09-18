// Complete type-2 residue path: classification scheduler, one shared Huffman
// reader, VQ expansion, and an accumulating spectral workspace.
module vorbis_residue_pipeline(
 input wire clk,input wire reset,input wire start,input wire [15:0] residue_type,
 input wire [12:0] workspace_length,input wire packet_buffered_end,input wire packet_exhausted,
 input wire [23:0] residue_begin,input wire [23:0] residue_end,input wire [23:0] partition_size,
 input wire [6:0] classifications,input wire [7:0] classbook,input wire [7:0] classbook_dimensions,
 output wire [5:0] class_query,input wire [7:0] class_cascade,
 output wire [2:0] pass_query,input wire [7:0] pass_book,
 input wire [31:0] bits,input wire [6:0] bits_available,
 output wire consume_valid,output wire [5:0] consume_count,
 output wire prefix_lookup_valid,output wire [5:0] prefix_lookup_book,
 output wire [7:0] prefix_lookup_bits,input wire prefix_result_valid,
 input wire prefix_hit,input wire [5:0] prefix_length,input wire [17:0] prefix_symbol,
 output wire [7:0] codebook_query,input wire [13:0] codebook_query_start,input wire [13:0] codebook_query_end,
 input wire [15:0] codebook_dimensions,input wire [1:0] codebook_lookup_type,input wire codebook_sequence,
 input wire [31:0] codebook_minimum,input wire [31:0] codebook_delta,
 input wire [13:0] codebook_multiplicand_start,input wire [13:0] codebook_multiplicand_count,
 output wire [13:0] active_query_address,input wire [31:0] active_query_entry,input wire [31:0] active_query_codeword,
 output wire [13:0] multiplicand_query_address,input wire [15:0] multiplicand_query_data,
 input wire read_valid,output wire read_ready,input wire [11:0] read_address,
 output wire read_data_valid,output wire signed [31:0] read_data,
 input wire set_valid,output wire set_ready,input wire [11:0] set_address,input wire signed [31:0] set_value,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,CLEAR_REQ=1,CLEAR_WAIT=2,LAUNCH=3,RUN=4,FINISH=5;
 reg [2:0] state=IDLE;reg task_active=0,scheduler_done_seen=0;
 reg abort_reset=0;
 reg [7:0] saved_classbook_dimensions=0;
 wire scheduler_ready,scheduler_done,scheduler_error,scheduler_hvalid,scheduler_hready,executor_exhausted;
 wire [7:0] scheduler_hbook;wire scheduler_symbol_valid;wire [17:0] scheduler_symbol;
 wire task_valid,task_ready;wire [7:0] task_book;wire [2:0] task_pass;wire [6:0] task_partition;
 wire [23:0] task_offset,task_length;wire executor_done,executor_error;
 wire workspace_clear_ready,workspace_clear_done,workspace_add_ready;
 wire residue_write_valid;wire [23:0] residue_write_address;wire signed [31:0] residue_write_value;
 wire scheduler_start=state==LAUNCH;
 wire workspace_clear_start=state==CLEAR_REQ&&workspace_clear_ready;
 // Vorbis applies the setup-header residue range to the current packet's
 // actual vector size. Short blocks therefore clamp ranges that were sized
 // for the stream's long block; decoding past this limit consumes unrelated
 // packet bits and corrupts every following stage.
 wire [23:0] limited_begin=residue_begin>workspace_length?workspace_length:residue_begin;
 wire [23:0] limited_end=residue_end>workspace_length?workspace_length:residue_end;
 assign ready=state==IDLE;

 vorbis_residue_scheduler scheduler(.clk(clk),.reset(reset||abort_reset),.start(scheduler_start),
  .residue_begin(limited_begin),.residue_end(limited_end),.partition_size(partition_size),
  .classifications(classifications),.classbook(classbook),.classbook_dimensions(saved_classbook_dimensions),
  .class_query(class_query),.class_cascade(class_cascade),.pass_query(pass_query),.pass_book(pass_book),
  .huffman_valid(scheduler_hvalid),.huffman_ready(scheduler_hready),.huffman_book(scheduler_hbook),
  .symbol_valid(scheduler_symbol_valid),.symbol(scheduler_symbol),
  .task_valid(task_valid),.task_ready(task_ready),.task_book(task_book),.task_pass(task_pass),
  .task_partition(task_partition),.task_offset(task_offset),.task_length(task_length),
  .ready(scheduler_ready),.done(scheduler_done),.error(scheduler_error));

 vorbis_residue_vector_task executor(.clk(clk),.reset(reset||abort_reset),
  .task_valid(task_valid),.task_ready(task_ready),.task_book(task_book),
  .packet_buffered_end(packet_buffered_end),.exhausted(executor_exhausted),
  .task_offset(task_offset),.task_length(task_length),
  .class_request_valid(scheduler_hvalid),.class_request_ready(scheduler_hready),
  .class_request_book(scheduler_hbook),.class_symbol_valid(scheduler_symbol_valid),
  .class_symbol_ready(1'b1),.class_symbol(scheduler_symbol),
  .bits(bits),.bits_available(bits_available),.consume_valid(consume_valid),.consume_count(consume_count),
  .prefix_lookup_valid(prefix_lookup_valid),.prefix_lookup_book(prefix_lookup_book),
  .prefix_lookup_bits(prefix_lookup_bits),.prefix_result_valid(prefix_result_valid),.prefix_hit(prefix_hit),
  .prefix_length(prefix_length),.prefix_symbol(prefix_symbol),.codebook_query(codebook_query),
  .codebook_query_start(codebook_query_start),.codebook_query_end(codebook_query_end),
  .codebook_dimensions(codebook_dimensions),.codebook_lookup_type(codebook_lookup_type),
  .codebook_sequence(codebook_sequence),.codebook_minimum(codebook_minimum),.codebook_delta(codebook_delta),
  .codebook_multiplicand_start(codebook_multiplicand_start),.codebook_multiplicand_count(codebook_multiplicand_count),
  .active_query_address(active_query_address),.active_query_entry(active_query_entry),
  .active_query_codeword(active_query_codeword),.multiplicand_query_address(multiplicand_query_address),
  .multiplicand_query_data(multiplicand_query_data),.write_valid(residue_write_valid),
  .write_ready(workspace_add_ready),.write_address(residue_write_address),.write_value(residue_write_value),
  .done(executor_done),.error(executor_error));

 vorbis_residue_workspace workspace(.clk(clk),.reset(reset||abort_reset),
  .clear_start(workspace_clear_start),.clear_length(workspace_length),
  .clear_ready(workspace_clear_ready),.clear_done(workspace_clear_done),
  .add_valid(residue_write_valid),.add_ready(workspace_add_ready),
  .add_address(residue_write_address[11:0]),.add_value(residue_write_value),
  .set_valid(set_valid),.set_ready(set_ready),.set_address(set_address),.set_value(set_value),
  .read_valid(read_valid),.read_ready(read_ready),.read_address(read_address),
  .read_data_valid(read_data_valid),.read_data(read_data));

 always @(posedge clk)begin
  if(reset)begin state<=IDLE;done<=0;error<=0;task_active<=0;scheduler_done_seen<=0;abort_reset<=0;end
  else begin
   done<=0;abort_reset<=0;
   if(scheduler_error||(executor_error&&!packet_buffered_end))error<=1;
   if(scheduler_done)scheduler_done_seen<=1;
   if(executor_done)task_active<=0;
   // A completing task and acceptance of its successor may coincide. The
   // newly accepted task must win so later phases cannot steal the workspace.
   if(task_valid&&task_ready)task_active<=1;
   if((executor_error&&packet_buffered_end)||executor_exhausted||(packet_exhausted&&state==RUN))begin
    task_active<=0;abort_reset<=1;state<=FINISH;
   end
   else case(state)
    IDLE:if(start)begin
     error<=0;task_active<=0;scheduler_done_seen<=0;
     saved_classbook_dimensions<=classbook_dimensions[7:0];
     if(residue_type!=2||residue_end>4096||residue_begin>residue_end)begin error<=1;state<=FINISH;end
     else state<=CLEAR_REQ;
    end
    CLEAR_REQ:if(workspace_clear_ready)state<=CLEAR_WAIT;
    CLEAR_WAIT:if(workspace_clear_done)state<=LAUNCH;
    LAUNCH:state<=RUN;
    RUN:if((scheduler_done_seen||scheduler_done)&&!task_active)state<=FINISH;
    FINISH:begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
