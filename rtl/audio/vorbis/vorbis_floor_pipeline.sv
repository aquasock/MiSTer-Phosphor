// Live audio-header + stereo Floor-1 pipeline. Configuration and Huffman RAM
// remain owned by the setup parser; this module only drives their query ports.
module vorbis_floor_pipeline(
 input wire clk,input wire reset,input wire audio_packet_start,input wire [7:0] channels,
 input wire [6:0] mode_count,input wire [63:0] mode_blockflags,input wire [511:0] mode_mappings,
 input wire [31:0] bits,input wire [6:0] bits_available,input wire packet_buffered_end,
 output wire consume_valid,output wire [5:0] consume_count,
 output wire [5:0] mapping_query,output wire mapping_channel_query,
 output wire [2:0] mapping_submap_query,input wire [3:0] mapping_query_mux,input wire [7:0] mapping_query_floor,
 output wire [5:0] floor_query,output wire [4:0] floor_part_query,
 output wire [3:0] floor_class_query,output wire [2:0] floor_subbook_query,output wire [6:0] floor_x_query,
 input wire [15:0] floor_query_type,input wire [4:0] floor_query_partitions,
 input wire [3:0] floor_query_partition_class,input wire [3:0] floor_query_class_dimensions,
 input wire [2:0] floor_query_class_subclasses,input wire [7:0] floor_query_class_masterbook,
 input wire [7:0] floor_query_subbook,input wire [2:0] floor_query_multiplier,
 input wire [3:0] floor_query_rangebits,input wire [15:0] floor_query_x,
 output wire prefix_lookup_valid,output wire [5:0] prefix_lookup_book,output wire [7:0] prefix_lookup_bits,
 input wire prefix_result_valid,input wire prefix_hit,input wire [5:0] prefix_length,input wire [17:0] prefix_symbol,
 output wire [7:0] codebook_query,input wire [13:0] codebook_query_start,input wire [13:0] codebook_query_end,
 output wire [13:0] active_query_address,input wire [31:0] active_query_entry,input wire [31:0] active_query_codeword,
 output wire packet_floors_done,output wire [1:0] channel_floor_present,
 output wire [5:0] packet_mode,output wire blockflag,output wire previous_window,output wire next_window,
 output wire point_valid,input wire point_ready,output wire floor_channel,
 output wire [6:0] point_index,output wire [15:0] point_x,output wire [8:0] point_y,output wire point_active,
 output wire packet_exhausted,output wire error
);
 wire control_consume,floor_consume,huffman_consume;
 wire [5:0] control_count,floor_count_bits,huffman_count;
 wire floor_start,floor_ready,floor_done,floor_present;
 wire [5:0] floor_number;
 wire huffman_request,huffman_ready,huffman_symbol_valid;
 wire [7:0] huffman_book;wire [17:0] huffman_symbol;
 wire control_error,floor_error,huffman_error,huffman_exhausted;
 wire pipeline_reset=reset|huffman_exhausted;
 assign packet_exhausted=huffman_exhausted;
 assign consume_valid=control_consume|floor_consume|huffman_consume;
 assign consume_count=control_consume?control_count:(floor_consume?floor_count_bits:huffman_count);
 assign error=control_error|floor_error|huffman_error|
  (control_consume&&floor_consume)|(control_consume&&huffman_consume)|(floor_consume&&huffman_consume);

 vorbis_audio_floor_control control(.clk(clk),.reset(pipeline_reset),.audio_packet_start(audio_packet_start),.channels(channels),
  .mode_count(mode_count),.mode_blockflags(mode_blockflags),.mode_mappings(mode_mappings),.bits(bits),.bits_available(bits_available),
  .consume_valid(control_consume),.consume_count(control_count),.mapping_query(mapping_query),
  .mapping_channel_query(mapping_channel_query),.mapping_query_mux(mapping_query_mux),.mapping_query_floor(mapping_query_floor),
  .mapping_submap_query(mapping_submap_query),.floor_start(floor_start),.floor_ready(floor_ready),.floor_number(floor_number),
  .floor_channel(floor_channel),.floor_done(floor_done),.floor_present(floor_present),.packet_floors_done(packet_floors_done),
  .channel_floor_present(channel_floor_present),.packet_mode(packet_mode),.blockflag(blockflag),
  .previous_window(previous_window),.next_window(next_window),.error(control_error));

 vorbis_floor1_unpack floor(.clk(clk),.reset(pipeline_reset),.start(floor_start),.floor_number(floor_number),
  .floor_query(floor_query),.floor_part_query(floor_part_query),.floor_class_query(floor_class_query),
  .floor_subbook_query(floor_subbook_query),.floor_x_query(floor_x_query),.floor_query_type(floor_query_type),
  .floor_query_partitions(floor_query_partitions),.floor_query_partition_class(floor_query_partition_class),
  .floor_query_class_dimensions(floor_query_class_dimensions),.floor_query_class_subclasses(floor_query_class_subclasses),
  .floor_query_class_masterbook(floor_query_class_masterbook),.floor_query_subbook(floor_query_subbook),
  .floor_query_multiplier(floor_query_multiplier),.floor_query_rangebits(floor_query_rangebits),.floor_query_x(floor_query_x),
  .bits_valid(bits_available!=0),.bits(bits),.bits_available(bits_available),.consume_valid(floor_consume),
  .consume_count(floor_count_bits),.huffman_valid(huffman_request),.huffman_ready(huffman_ready),.huffman_book(huffman_book),
  .symbol_valid(huffman_symbol_valid),.symbol(huffman_symbol),.ready(floor_ready),.done(floor_done),.present(floor_present),
  .error(floor_error),.point_valid(point_valid),.point_ready(point_ready),.point_index(point_index),.point_x(point_x),
  .point_y(point_y),.point_active(point_active));

 vorbis_huffman_reader reader(.clk(clk),.reset(pipeline_reset),.request_valid(huffman_request),.request_ready(huffman_ready),
  .request_book(huffman_book),.packet_buffered_end(packet_buffered_end),.bits(bits),.bits_available(bits_available),.consume_valid(huffman_consume),
  .consume_count(huffman_count),.prefix_lookup_valid(prefix_lookup_valid),.prefix_lookup_book(prefix_lookup_book),
  .prefix_lookup_bits(prefix_lookup_bits),.prefix_result_valid(prefix_result_valid),.prefix_hit(prefix_hit),
  .prefix_length(prefix_length),.prefix_symbol(prefix_symbol),.codebook_query(codebook_query),
  .codebook_query_start(codebook_query_start),.codebook_query_end(codebook_query_end),
  .active_query_address(active_query_address),.active_query_entry(active_query_entry),.active_query_codeword(active_query_codeword),
  .symbol_valid(huffman_symbol_valid),.symbol_ready(1'b1),.symbol(huffman_symbol),.symbol_length(),.exhausted(huffman_exhausted),.error(huffman_error));
endmodule
