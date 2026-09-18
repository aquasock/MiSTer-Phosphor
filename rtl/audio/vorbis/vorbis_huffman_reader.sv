// Connects packet lookahead, the short-code prefix table, and the canonical
// fallback scanner into one transactional codebook-symbol reader.
module vorbis_huffman_reader(
 input wire clk,input wire reset,
 input wire request_valid,output wire request_ready,input wire [7:0] request_book,input wire packet_buffered_end,
 input wire [31:0] bits,input wire [6:0] bits_available,
 output reg consume_valid=0,output reg [5:0] consume_count=0,
 output reg prefix_lookup_valid=0,output reg [5:0] prefix_lookup_book=0,
 output reg [7:0] prefix_lookup_bits=0,input wire prefix_result_valid,
 input wire prefix_hit,input wire [5:0] prefix_length,input wire [17:0] prefix_symbol,
 output reg [7:0] codebook_query=0,input wire [13:0] codebook_query_start,input wire [13:0] codebook_query_end,
 output wire [13:0] active_query_address,input wire [31:0] active_query_entry,input wire [31:0] active_query_codeword,
 output reg symbol_valid=0,input wire symbol_ready,output reg [17:0] symbol=0,
 output reg [5:0] symbol_length=0,output reg exhausted=0,output reg error=0
);
 localparam IDLE=0,PREFIX_WAIT_BITS=1,PREFIX_WAIT=2,FALLBACK_START=3,
  FALLBACK_FEED=4,CONSUME=5,CONSUME_GAP=6,OUTPUT=7;
 reg [2:0] state=IDLE;
 reg scalar_start=0,scalar_bit_valid=0,scalar_bit_data=0;
 wire scalar_bit_ready,scalar_valid,scalar_error;
 wire [17:0] scalar_symbol;wire [5:0] scalar_length;
 reg [5:0] fallback_bit=0;
 reg [5:0] fallback_seed_length=0;
 reg bit_inflight=0;
 assign request_ready=state==IDLE;
 vorbis_huffman_decoder scalar(.clk(clk),.reset(reset),.start(scalar_start),
  .start_prefix(fallback_seed_length==0?32'd0:{24'd0,bits[7:0]}),.start_length(fallback_seed_length),
  .table_start(codebook_query_start),.table_end(codebook_query_end),
  .bit_valid(scalar_bit_valid),.bit_data(scalar_bit_data),.bit_ready(scalar_bit_ready),
  .table_address(active_query_address),.table_entry(active_query_entry),.table_codeword(active_query_codeword),
  .symbol_valid(scalar_valid),.symbol_ready(1'b1),.symbol(scalar_symbol),.symbol_length(scalar_length),.error(scalar_error));
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;consume_valid<=0;prefix_lookup_valid<=0;symbol_valid<=0;exhausted<=0;error<=0;scalar_start<=0;scalar_bit_valid<=0;end
  else begin
   consume_valid<=0;prefix_lookup_valid<=0;scalar_start<=0;scalar_bit_valid<=0;
   if(symbol_valid&&symbol_ready)symbol_valid<=0;
   if(scalar_error)error<=1;
   case(state)
    IDLE:if(request_valid)begin
     exhausted<=0;
     if(request_book>=64)begin error<=1;end
     else begin codebook_query<=request_book;prefix_lookup_book<=request_book[5:0];state<=PREFIX_WAIT_BITS;end
    end
    PREFIX_WAIT_BITS:begin
     if(bits_available>=8)begin prefix_lookup_bits<=bits[7:0];prefix_lookup_valid<=1;state<=PREFIX_WAIT;end
     // Near packet end fewer than eight bits may remain, yet still contain a
     // complete short codeword. The canonical scanner can begin immediately
     // and naturally stalls if a later bit has not arrived from transport.
     else if(bits_available!=0)begin fallback_seed_length<=0;state<=FALLBACK_START;end
    end
    PREFIX_WAIT:if(prefix_result_valid)begin
     if(prefix_hit)begin symbol<=prefix_symbol;symbol_length<=prefix_length;state<=CONSUME;end
     else begin fallback_seed_length<=8;state<=FALLBACK_START;end
    end
    FALLBACK_START:begin scalar_start<=1;fallback_bit<=fallback_seed_length;bit_inflight<=0;state<=FALLBACK_FEED;end
    FALLBACK_FEED:begin
     if(scalar_valid)begin symbol<=scalar_symbol;symbol_length<=scalar_length;state<=CONSUME;end
     else if(bit_inflight)bit_inflight<=0;
     else if(scalar_bit_ready&&bits_available>fallback_bit)begin
      scalar_bit_data<=bits[fallback_bit];scalar_bit_valid<=1;fallback_bit<=fallback_bit+1'b1;bit_inflight<=1;
     end else if(packet_buffered_end&&fallback_bit>=bits_available)begin exhausted<=1;state<=IDLE;end
     else if(fallback_bit==32)begin error<=1;state<=IDLE;end
    end
    CONSUME:begin consume_valid<=1;consume_count<=symbol_length;state<=CONSUME_GAP;end
    // The packet reservoir has observed consume_valid by this edge, so the
    // decoded symbol can be delivered immediately without a separate output
    // staging cycle.
    CONSUME_GAP:begin symbol_valid<=1;if(symbol_ready)state<=IDLE;else state<=OUTPUT;end
    OUTPUT:begin symbol_valid<=1;if(symbol_ready)state<=IDLE;end
   endcase
  end
 end
endmodule
