// Complete bounded-profile Ogg Vorbis stream decoder.  This wrapper owns the
// header/setup memories and exposes the same byte-stream/PCM handshake used by
// the other player decoders.
module vorbis_stream_decoder(
 input wire clk,input wire reset,
 input wire byte_valid,input wire [7:0] byte_data,output wire byte_ready,
 output wire pcm_valid,input wire pcm_ready,
 output wire signed [31:0] pcm_left,output wire signed [31:0] pcm_right,
 output wire [31:0] sample_rate,output wire ready,output wire error
);
 wire packet_valid,packet_start,packet_end,packet_ready;wire [7:0] packet_data;wire [63:0] granule_position;
 wire ogg_error,header_ready,setup_ready,decoder_ready,header_error,identification_valid,headers_valid;
 wire [7:0] channels;wire [11:0] blocksize_short,blocksize_long;wire [1:0] header_number;
 wire setup_valid,setup_error;wire [7:0] codebook_count;wire [13:0] active_entries,multiplicand_count;
 wire [6:0] floor_count,residue_count,mapping_count,mode_count;wire [63:0] mode_blockflags;wire [511:0] mode_mappings;
 wire [5:0] mapping_query;wire [2:0] mapping_submap_query;wire mapping_channel_query;wire [7:0] mapping_coupling_query;
 wire [4:0] mapping_query_submaps;wire [3:0] mapping_query_mux;wire [7:0] mapping_query_floor,mapping_query_residue;
 wire [8:0] mapping_query_coupling_steps;wire mapping_query_magnitude,mapping_query_angle;
 wire [5:0] floor_query;wire [4:0] floor_part_query;wire [3:0] floor_class_query;wire [2:0] floor_subbook_query;
 wire [6:0] floor_x_query;wire [15:0] floor_query_type,floor_query_x;wire [4:0] floor_query_partitions;
 wire [3:0] floor_query_partition_class,floor_query_class_dimensions;wire [2:0] floor_query_class_subclasses;
 wire [7:0] floor_query_class_masterbook,floor_query_subbook;wire [2:0] floor_query_multiplier;wire [3:0] floor_query_rangebits;
 wire [5:0] residue_query,residue_class_query;wire [2:0] residue_pass_query;wire [15:0] residue_query_type;
 wire [23:0] residue_query_begin,residue_query_end,residue_query_partition_size;wire [6:0] residue_query_classifications;
 wire [7:0] residue_query_classbook,residue_query_cascade,residue_query_book;
 wire [7:0] codebook_query;wire [13:0] codebook_query_start,codebook_query_end,decoder_active_address,setup_active_address;
 wire [31:0] active_query_entry,active_query_codeword;wire [13:0] multiplicand_query_address;wire [15:0] multiplicand_query_data;
 wire [15:0] codebook_query_dimensions;wire [23:0] codebook_query_entries;wire [1:0] codebook_query_lookup_type;
 wire codebook_query_sequence;wire [31:0] codebook_query_minimum,codebook_query_delta;
 wire [13:0] codebook_query_multiplicand_start,codebook_query_multiplicand_count;
 wire prefix_lookup_valid,prefix_result_valid,prefix_hit;wire [5:0] prefix_lookup_book,prefix_result_length;
 wire [7:0] prefix_lookup_bits;wire [17:0] prefix_result_symbol;wire prefix_ready,prefix_error;
 wire prefix_leaf_valid,prefix_leaf_ready;wire [5:0] prefix_leaf_book,prefix_leaf_length;wire [31:0] prefix_leaf_codeword;
 wire [17:0] prefix_leaf_symbol;wire builder_done,builder_error;wire [13:0] builder_address;
 wire busy,packet_done,decoder_error;wire [10:0] pcm_index;
 wire gated_packet_valid=packet_valid&&packet_ready;
 wire gate=!setup_valid||builder_done;
 assign packet_ready=header_ready&&setup_ready&&decoder_ready&&gate;
 assign setup_active_address=builder_done?decoder_active_address:builder_address;
 wire [5:0] prefix_length=prefix_result_length;wire [17:0] prefix_symbol=prefix_result_symbol;
 assign ready=headers_valid&&builder_done&&!error;
 assign error=ogg_error|header_error|setup_error|prefix_error|builder_error|decoder_error;

 ogg_packet_reader ogg(.clk(clk),.reset(reset),.byte_valid(byte_valid),.byte_data(byte_data),.byte_ready(byte_ready),
  .packet_valid(packet_valid),.packet_data(packet_data),.packet_start(packet_start),.packet_end(packet_end),
  .packet_ready(packet_ready),.granule_position(granule_position),.error(ogg_error));
 vorbis_header_parser headers(.clk(clk),.reset(reset),.packet_valid(gated_packet_valid),.packet_data(packet_data),
  .packet_start(packet_start),.packet_end(packet_end),.packet_enable(packet_ready),.packet_ready(header_ready),
  .identification_valid(identification_valid),.headers_valid(headers_valid),.error(header_error),.channels(channels),
  .sample_rate(sample_rate),.blocksize_short(blocksize_short),.blocksize_long(blocksize_long),.header_number(header_number));
 vorbis_setup_codebooks setup(.*,.packet_valid(gated_packet_valid),.packet_ready(setup_ready),
  .valid(setup_valid),.error(setup_error),.active_query_address(setup_active_address));
 vorbis_huffman_prefix prefix(.clk(clk),.reset(reset),.leaf_valid(prefix_leaf_valid),.leaf_ready(prefix_leaf_ready),
  .leaf_book(prefix_leaf_book),.leaf_codeword(prefix_leaf_codeword),.leaf_length(prefix_leaf_length),.leaf_symbol(prefix_leaf_symbol),
  .lookup_valid(prefix_lookup_valid),.lookup_book(prefix_lookup_book),.lookup_bits(prefix_lookup_bits),
  .lookup_result_valid(prefix_result_valid),.lookup_hit(prefix_hit),.lookup_length(prefix_result_length),
  .lookup_symbol(prefix_result_symbol),.ready(prefix_ready),.error(prefix_error));
 vorbis_prefix_builder builder(.clk(clk),.reset(reset),.setup_valid(setup_valid),.active_entries(active_entries),
  .active_query_address(builder_address),.active_query_entry(active_query_entry),.active_query_codeword(active_query_codeword),
  .prefix_ready(prefix_ready),.leaf_valid(prefix_leaf_valid),.leaf_ready(prefix_leaf_ready),.leaf_book(prefix_leaf_book),
  .leaf_codeword(prefix_leaf_codeword),.leaf_length(prefix_leaf_length),.leaf_symbol(prefix_leaf_symbol),
  .done(builder_done),.error(builder_error));
 vorbis_audio_decoder decoder(.*,.packet_valid(gated_packet_valid),.packet_ready(decoder_ready),
  .active_query_address(decoder_active_address),.error(decoder_error));
endmodule
