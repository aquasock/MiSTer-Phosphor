// Executes one residue vector-book task. Type-2 residue stores the two
// channels as one interleaved scalar vector, so each expanded codebook value
// advances one consecutive workspace address.
module vorbis_residue_vector_task(
 input wire clk,input wire reset,
 input wire task_valid,output wire task_ready,input wire [7:0] task_book,
 input wire packet_buffered_end,output wire exhausted,
 input wire [23:0] task_offset,input wire [23:0] task_length,
 input wire class_request_valid,output wire class_request_ready,input wire [7:0] class_request_book,
 output wire class_symbol_valid,input wire class_symbol_ready,output wire [17:0] class_symbol,

 input wire [31:0] bits,input wire [6:0] bits_available,
 output wire consume_valid,output wire [5:0] consume_count,
 output wire prefix_lookup_valid,output wire [5:0] prefix_lookup_book,
 output wire [7:0] prefix_lookup_bits,input wire prefix_result_valid,
 input wire prefix_hit,input wire [5:0] prefix_length,input wire [17:0] prefix_symbol,

 output wire [7:0] codebook_query,input wire [13:0] codebook_query_start,
 input wire [13:0] codebook_query_end,input wire [15:0] codebook_dimensions,
 input wire [1:0] codebook_lookup_type,input wire codebook_sequence,
 input wire [31:0] codebook_minimum,input wire [31:0] codebook_delta,
 input wire [13:0] codebook_multiplicand_start,input wire [13:0] codebook_multiplicand_count,
 output wire [13:0] active_query_address,input wire [31:0] active_query_entry,
 input wire [31:0] active_query_codeword,
 output wire [13:0] multiplicand_query_address,input wire [15:0] multiplicand_query_data,

 output wire write_valid,input wire write_ready,output wire [23:0] write_address,
 output wire signed [31:0] write_value,
 output reg done=0,output reg error=0
);
 localparam IDLE=0,HREQ=1,HWAIT=2,VSTART=3,VECTOR=4,FINISH=5;
 reg [2:0] state=IDLE;
 reg [7:0] saved_book=0;
 reg [23:0] saved_offset=0,saved_length=0,produced=0;
 reg [17:0] saved_symbol=0;
 reg h_owner_class=0,class_inflight=0;

 wire h_request_ready,h_symbol_valid,h_error,h_exhausted;
 wire [17:0] h_symbol;
 wire [7:0] h_codebook_query;
 wire v_ready,v_value_valid,v_done,v_error;
 wire [7:0] v_codebook_query;
 wire [15:0] v_value_index;
 wire signed [31:0] v_value;
 wire accepting_value=(produced<saved_length);
 wire v_value_ready=accepting_value?write_ready:1'b1;

 wire h_request_valid=(state==HREQ)||(state==IDLE&&!task_valid&&!class_inflight&&class_request_valid);
 wire [7:0] h_request_book=(state==HREQ)?saved_book:class_request_book;
 assign task_ready=state==IDLE&&!class_inflight;
 assign class_request_ready=state==IDLE&&!task_valid&&!class_inflight&&h_request_ready;
 assign class_symbol_valid=h_symbol_valid&&h_owner_class;
 assign class_symbol=h_symbol;
 assign codebook_query=(state==VSTART||state==VECTOR)?v_codebook_query:h_codebook_query;
 assign write_valid=(state==VECTOR)&&accepting_value&&v_value_valid;
 assign write_address=saved_offset+produced;
 assign write_value=v_value;

 vorbis_huffman_reader huffman(.clk(clk),.reset(reset),
  .request_valid(h_request_valid),.request_ready(h_request_ready),.request_book(h_request_book),
  .packet_buffered_end(packet_buffered_end),
  .bits(bits),.bits_available(bits_available),.consume_valid(consume_valid),.consume_count(consume_count),
  .prefix_lookup_valid(prefix_lookup_valid),.prefix_lookup_book(prefix_lookup_book),
  .prefix_lookup_bits(prefix_lookup_bits),.prefix_result_valid(prefix_result_valid),
  .prefix_hit(prefix_hit),.prefix_length(prefix_length),.prefix_symbol(prefix_symbol),
  .codebook_query(h_codebook_query),.codebook_query_start(codebook_query_start),
  .codebook_query_end(codebook_query_end),.active_query_address(active_query_address),
  .active_query_entry(active_query_entry),.active_query_codeword(active_query_codeword),
  .symbol_valid(h_symbol_valid),.symbol_ready(h_owner_class?class_symbol_ready:(state==HWAIT)),.symbol(h_symbol),
  .symbol_length(),.exhausted(h_exhausted),.error(h_error));
 assign exhausted=h_exhausted;

 vorbis_codebook_vector vector(.clk(clk),.reset(reset),.start(state==VSTART),
  .book(saved_book),.entry(saved_symbol),.codebook_query(v_codebook_query),
  .codebook_dimensions(codebook_dimensions),.codebook_lookup_type(codebook_lookup_type),
  .codebook_sequence(codebook_sequence),.codebook_minimum(codebook_minimum),
  .codebook_delta(codebook_delta),.codebook_multiplicand_start(codebook_multiplicand_start),
  .codebook_multiplicand_count(codebook_multiplicand_count),
  .multiplicand_query_address(multiplicand_query_address),
  .multiplicand_query_data(multiplicand_query_data),.ready(v_ready),
  .value_valid(v_value_valid),.value_ready(v_value_ready),.value_index(v_value_index),
  .value(v_value),.done(v_done),.error(v_error));

 always @(posedge clk)begin
  if(reset)begin state<=IDLE;done<=0;error<=0;produced<=0;h_owner_class<=0;class_inflight<=0;end
  else begin
   done<=0;
   if(h_error||v_error)begin error<=1;state<=FINISH;end
   if(class_request_valid&&class_request_ready)begin h_owner_class<=1;class_inflight<=1;end
   if(class_symbol_valid&&class_symbol_ready)begin h_owner_class<=0;class_inflight<=0;end
   if(!h_error&&!v_error)case(state)
    IDLE:if(task_valid)begin
     saved_book<=task_book;saved_offset<=task_offset;saved_length<=task_length;
     produced<=0;error<=0;
     if(task_length==0)state<=FINISH;else state<=HREQ;
    end
    HREQ:if(h_request_ready)state<=HWAIT;
    HWAIT:if(h_symbol_valid&&!h_owner_class)begin saved_symbol<=h_symbol;state<=VSTART;end
    VSTART:if(v_ready)state<=VECTOR;
    VECTOR:begin
     if(v_value_valid&&v_value_ready&&accepting_value)produced<=produced+1'b1;
     if(v_done)begin
      if(produced>=saved_length)state<=FINISH;
      else state<=HREQ;
     end
    end
    FINISH:begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
