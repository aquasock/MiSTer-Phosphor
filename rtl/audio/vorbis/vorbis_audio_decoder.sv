// Integrated stereo Vorbis-I audio-packet decoder for the bounded MiSTer
// profile. Setup/header storage remains in vorbis_setup_codebooks; this shell
// arbitrates its query ports and connects packet bits through to PCM.
module vorbis_audio_decoder(
 input wire clk,input wire reset,
 input wire packet_valid,input wire [7:0] packet_data,input wire packet_start,input wire packet_end,
 output wire packet_ready,
 input wire [7:0] channels,input wire [6:0] mode_count,input wire [63:0] mode_blockflags,input wire [511:0] mode_mappings,
 output wire [5:0] mapping_query,output wire [2:0] mapping_submap_query,output wire mapping_channel_query,
 output wire [7:0] mapping_coupling_query,input wire [4:0] mapping_query_submaps,
 input wire [3:0] mapping_query_mux,input wire [7:0] mapping_query_floor,input wire [7:0] mapping_query_residue,
 input wire [8:0] mapping_query_coupling_steps,input wire mapping_query_magnitude,input wire mapping_query_angle,
 output wire [5:0] floor_query,output wire [4:0] floor_part_query,output wire [3:0] floor_class_query,
 output wire [2:0] floor_subbook_query,output wire [6:0] floor_x_query,
 input wire [15:0] floor_query_type,input wire [4:0] floor_query_partitions,
 input wire [3:0] floor_query_partition_class,input wire [3:0] floor_query_class_dimensions,
 input wire [2:0] floor_query_class_subclasses,input wire [7:0] floor_query_class_masterbook,
 input wire [7:0] floor_query_subbook,input wire [2:0] floor_query_multiplier,
 input wire [3:0] floor_query_rangebits,input wire [15:0] floor_query_x,
 output wire [5:0] residue_query,output wire [5:0] residue_class_query,output wire [2:0] residue_pass_query,
 input wire [15:0] residue_query_type,input wire [23:0] residue_query_begin,input wire [23:0] residue_query_end,
 input wire [23:0] residue_query_partition_size,input wire [6:0] residue_query_classifications,
 input wire [7:0] residue_query_classbook,input wire [7:0] residue_query_cascade,input wire [7:0] residue_query_book,
 output wire [7:0] codebook_query,input wire [13:0] codebook_query_start,input wire [13:0] codebook_query_end,
 output wire [13:0] active_query_address,input wire [31:0] active_query_entry,input wire [31:0] active_query_codeword,
 output wire [13:0] multiplicand_query_address,input wire [15:0] multiplicand_query_data,
 input wire [15:0] codebook_query_dimensions,input wire [1:0] codebook_query_lookup_type,input wire codebook_query_sequence,
 input wire [31:0] codebook_query_minimum,input wire [31:0] codebook_query_delta,
 input wire [13:0] codebook_query_multiplicand_start,input wire [13:0] codebook_query_multiplicand_count,
 output wire prefix_lookup_valid,output wire [5:0] prefix_lookup_book,output wire [7:0] prefix_lookup_bits,
 input wire prefix_result_valid,input wire prefix_hit,input wire [5:0] prefix_length,input wire [17:0] prefix_symbol,
 output wire pcm_valid,input wire pcm_ready,output wire [10:0] pcm_index,
 output wire signed [31:0] pcm_left,output wire signed [31:0] pcm_right,
 output wire busy,output wire packet_done,output wire error
);
 wire audio_packet_start,bits_valid,packet_buffered_end,bits_consume,finish_packet,bits_error;
 wire [31:0] bits;wire [6:0] bits_available;wire [5:0] bits_consume_count;
 wire [3:0] phase;
 wire seq_floor_start,seq_residue_start,seq_coupling_start,seq_floor0_start,seq_floor1_start,seq_synthesis_start;
 wire floor_done,floor_packet_exhausted,residue_done,coupling_done,floor0_done,floor1_done,synthesis_done;
 wire residue_ready,coupling_ready,floor0_ready,floor1_ready,synthesis_ready;
 wire floor_error,residue_error,coupling_error,floor0_error,floor1_error,synthesis_error,sequence_error;
 wire [5:0] floor_mapping_query;wire floor_mapping_channel;wire [2:0] floor_mapping_submap;
 wire [5:0] packet_mode;wire blockflag,previous_window,next_window;wire [1:0] floor_present;
 wire floor_point_valid,floor_point_ready,floor_channel,floor_point_active;
 wire [6:0] floor_point_index;wire [15:0] floor_point_x;wire [8:0] floor_point_y;
 reg [2:0] floor_multiplier0=1,floor_multiplier1=1;
 wire floor_consume,residue_consume;wire [5:0] floor_consume_count,residue_consume_count;
 wire floor_prefix_valid,residue_prefix_valid;wire [5:0] floor_prefix_book,residue_prefix_book;
 wire [7:0] floor_prefix_bits,residue_prefix_bits;
 wire [7:0] floor_codebook_query,residue_codebook_query;wire [13:0] floor_active_query,residue_active_query;
 wire [13:0] residue_multiplicand_query;
 wire [5:0] residue_class;wire [2:0] residue_pass;
 wire workspace_read_valid,workspace_read_ready,workspace_read_data_valid;
 wire [11:0] workspace_read_address;wire signed [31:0] workspace_read_data;
 wire workspace_set_valid,workspace_set_ready;wire [11:0] workspace_set_address;wire signed [31:0] workspace_set_value;
 wire coupling_read_valid,coupling_set_valid;wire [11:0] coupling_read_address,coupling_set_address;
 wire signed [31:0] coupling_set_value;
 wire apply0_read_valid,apply0_set_valid;wire [11:0] apply0_read_address,apply0_set_address;wire signed [31:0] apply0_set_value;
 wire apply1_read_valid,apply1_set_valid;wire [11:0] apply1_read_address,apply1_set_address;wire signed [31:0] apply1_set_value;
 wire synth_read_valid;wire [11:0] synth_read_address;
 wire [10:0] spectral_bins=blockflag?11'd1024:11'd128;

 vorbis_packet_bits packet_bits(.clk(clk),.reset(reset),.packet_valid(packet_valid),.packet_data(packet_data),
  .packet_start(packet_start),.packet_end(packet_end),.packet_ready(packet_ready),.audio_packet_start(audio_packet_start),
  .bits_valid(bits_valid),.bits(bits),.bits_available(bits_available),.consume_valid(bits_consume),
  .consume_count(bits_consume_count),.packet_buffered_end(packet_buffered_end),.finish_packet(finish_packet),.error(bits_error));
 vorbis_audio_sequence packet_sequence(.clk(clk),.reset(reset),.packet_start(audio_packet_start),
  .packet_exhausted((packet_buffered_end&&bits_available==0)|floor_packet_exhausted),
  .floor_start(seq_floor_start),.floor_done(floor_done),.residue_start(seq_residue_start),.residue_ready(residue_ready),
  .residue_done(residue_done),.coupling_start(seq_coupling_start),.coupling_ready(coupling_ready),.coupling_done(coupling_done),
  .floor0_start(seq_floor0_start),.floor0_ready(floor0_ready),.floor0_done(floor0_done),
  .floor1_start(seq_floor1_start),.floor1_ready(floor1_ready),.floor1_done(floor1_done),
  .synthesis_start(seq_synthesis_start),.synthesis_ready(synthesis_ready),.synthesis_done(synthesis_done),
  .finish_packet(finish_packet),.busy(busy),.packet_done(packet_done),
  .stage_error(bits_error|floor_error|residue_error|coupling_error|floor0_error|floor1_error|synthesis_error),
  .error(sequence_error),.phase(phase));

 vorbis_floor_pipeline floors(.clk(clk),.reset(reset),.audio_packet_start(seq_floor_start),.channels(channels),
  .mode_count(mode_count),.mode_blockflags(mode_blockflags),.mode_mappings(mode_mappings),.bits(bits),.bits_available(bits_available),
  .packet_buffered_end(packet_buffered_end),
  .consume_valid(floor_consume),.consume_count(floor_consume_count),.mapping_query(floor_mapping_query),
  .mapping_channel_query(floor_mapping_channel),.mapping_submap_query(floor_mapping_submap),
  .mapping_query_mux(mapping_query_mux),.mapping_query_floor(mapping_query_floor),
  .floor_query(floor_query),.floor_part_query(floor_part_query),.floor_class_query(floor_class_query),
  .floor_subbook_query(floor_subbook_query),.floor_x_query(floor_x_query),.floor_query_type(floor_query_type),
  .floor_query_partitions(floor_query_partitions),.floor_query_partition_class(floor_query_partition_class),
  .floor_query_class_dimensions(floor_query_class_dimensions),.floor_query_class_subclasses(floor_query_class_subclasses),
  .floor_query_class_masterbook(floor_query_class_masterbook),.floor_query_subbook(floor_query_subbook),
  .floor_query_multiplier(floor_query_multiplier),.floor_query_rangebits(floor_query_rangebits),.floor_query_x(floor_query_x),
  .prefix_lookup_valid(floor_prefix_valid),.prefix_lookup_book(floor_prefix_book),.prefix_lookup_bits(floor_prefix_bits),
  .prefix_result_valid(prefix_result_valid),.prefix_hit(prefix_hit),.prefix_length(prefix_length),.prefix_symbol(prefix_symbol),
  .codebook_query(floor_codebook_query),.codebook_query_start(codebook_query_start),.codebook_query_end(codebook_query_end),
  .active_query_address(floor_active_query),.active_query_entry(active_query_entry),.active_query_codeword(active_query_codeword),
  .packet_floors_done(floor_done),.channel_floor_present(floor_present),.packet_mode(packet_mode),.blockflag(blockflag),
  .previous_window(previous_window),.next_window(next_window),.point_valid(floor_point_valid),.point_ready(floor_point_ready),
  .floor_channel(floor_channel),.point_index(floor_point_index),.point_x(floor_point_x),.point_y(floor_point_y),
  .point_active(floor_point_active),.packet_exhausted(floor_packet_exhausted),.error(floor_error));

 assign mapping_query=floor_mapping_query;
 assign mapping_channel_query=phase==1?floor_mapping_channel:1'b0;
 assign mapping_submap_query=phase==1?floor_mapping_submap:3'd0;
 assign mapping_coupling_query=coupler_query;
 assign residue_query=mapping_query_residue[5:0];assign residue_class_query=residue_class;assign residue_pass_query=residue_pass;
 wire [7:0] residue_classbook_dimension_query=residue_query_classbook;
 wire [7:0] selected_codebook=(phase==1)?floor_codebook_query:
  ((phase==2)?residue_classbook_dimension_query:residue_codebook_query);
 assign codebook_query=selected_codebook;
 assign active_query_address=phase==1?floor_active_query:residue_active_query;
 assign multiplicand_query_address=residue_multiplicand_query;
 assign prefix_lookup_valid=phase==1?floor_prefix_valid:residue_prefix_valid;
 assign prefix_lookup_book=phase==1?floor_prefix_book:residue_prefix_book;
 assign prefix_lookup_bits=phase==1?floor_prefix_bits:residue_prefix_bits;
 assign bits_consume=phase==1?floor_consume:residue_consume;
 assign bits_consume_count=phase==1?floor_consume_count:residue_consume_count;

 always @(posedge clk)begin
  if(reset)begin floor_multiplier0<=1;floor_multiplier1<=1;end
  else if(floor_point_valid)begin if(floor_channel)floor_multiplier1<=floor_query_multiplier;else floor_multiplier0<=floor_query_multiplier;end
 end

 vorbis_residue_pipeline residues(.clk(clk),.reset(reset),.start(seq_residue_start),.residue_type(residue_query_type),
  .workspace_length({1'b0,spectral_bins,1'b0}),.packet_buffered_end(packet_buffered_end),
  .packet_exhausted(packet_buffered_end&&bits_available==0),
  .residue_begin(residue_query_begin),.residue_end(residue_query_end),
  .partition_size(residue_query_partition_size),.classifications(residue_query_classifications),.classbook(residue_query_classbook),
  .classbook_dimensions(codebook_query_dimensions[7:0]),.class_query(residue_class),.class_cascade(residue_query_cascade),
  .pass_query(residue_pass),.pass_book(residue_query_book),.bits(bits),.bits_available(bits_available),
  .consume_valid(residue_consume),.consume_count(residue_consume_count),.prefix_lookup_valid(residue_prefix_valid),
  .prefix_lookup_book(residue_prefix_book),.prefix_lookup_bits(residue_prefix_bits),.prefix_result_valid(prefix_result_valid),
  .prefix_hit(prefix_hit),.prefix_length(prefix_length),.prefix_symbol(prefix_symbol),.codebook_query(residue_codebook_query),
  .codebook_query_start(codebook_query_start),.codebook_query_end(codebook_query_end),.codebook_dimensions(codebook_query_dimensions),
  .codebook_lookup_type(codebook_query_lookup_type),.codebook_sequence(codebook_query_sequence),
  .codebook_minimum(codebook_query_minimum),.codebook_delta(codebook_query_delta),
  .codebook_multiplicand_start(codebook_query_multiplicand_start),.codebook_multiplicand_count(codebook_query_multiplicand_count),
  .active_query_address(residue_active_query),.active_query_entry(active_query_entry),.active_query_codeword(active_query_codeword),
  .multiplicand_query_address(residue_multiplicand_query),.multiplicand_query_data(multiplicand_query_data),
  .read_valid(workspace_read_valid),.read_ready(workspace_read_ready),.read_address(workspace_read_address),
  .read_data_valid(workspace_read_data_valid),.read_data(workspace_read_data),.set_valid(workspace_set_valid),
  .set_ready(workspace_set_ready),.set_address(workspace_set_address),.set_value(workspace_set_value),
  .ready(residue_ready),.done(residue_done),.error(residue_error));

 wire [7:0] coupler_query;
 vorbis_inverse_coupling coupling(.clk(clk),.reset(reset),.start(seq_coupling_start),
  .coupling_steps(mapping_query_coupling_steps),.spectral_bins({1'b0,spectral_bins}),.coupling_query(coupler_query),
  .coupling_magnitude(mapping_query_magnitude),.coupling_angle(mapping_query_angle),
  .read_valid(coupling_read_valid),.read_ready(workspace_read_ready),.read_address(coupling_read_address),
  .read_data_valid(workspace_read_data_valid),.read_data(workspace_read_data),.set_valid(coupling_set_valid),
  .set_ready(workspace_set_ready),.set_address(coupling_set_address),.set_value(coupling_set_value),
  .ready(coupling_ready),.done(coupling_done),.error(coupling_error));

 assign floor_point_ready=floor_channel?apply1_point_ready:apply0_point_ready;
 wire apply0_point_ready,apply1_point_ready;
 vorbis_floor1_apply apply0(.clk(clk),.reset(reset),.load_start(seq_floor_start),
  .point_valid(floor_point_valid&&!floor_channel),.point_ready(apply0_point_ready),.point_x(floor_point_x),.point_y(floor_point_y),
  .point_active(floor_point_active),.apply_start(seq_floor0_start),.floor_present(floor_present[0]),.channel(1'b0),
  .spectral_bins({1'b0,spectral_bins}),.multiplier(floor_multiplier0),.read_valid(apply0_read_valid),
  .read_ready(workspace_read_ready),.read_address(apply0_read_address),.read_data_valid(workspace_read_data_valid),
  .read_data(workspace_read_data),.set_valid(apply0_set_valid),.set_ready(workspace_set_ready),
  .set_address(apply0_set_address),.set_value(apply0_set_value),.ready(floor0_ready),.done(floor0_done),.error(floor0_error));
 vorbis_floor1_apply apply1(.clk(clk),.reset(reset),.load_start(seq_floor_start),
  .point_valid(floor_point_valid&&floor_channel),.point_ready(apply1_point_ready),.point_x(floor_point_x),.point_y(floor_point_y),
  .point_active(floor_point_active),.apply_start(seq_floor1_start),.floor_present(floor_present[1]),.channel(1'b1),
  .spectral_bins({1'b0,spectral_bins}),.multiplier(floor_multiplier1),.read_valid(apply1_read_valid),
  .read_ready(workspace_read_ready),.read_address(apply1_read_address),.read_data_valid(workspace_read_data_valid),
  .read_data(workspace_read_data),.set_valid(apply1_set_valid),.set_ready(workspace_set_ready),
  .set_address(apply1_set_address),.set_value(apply1_set_value),.ready(floor1_ready),.done(floor1_done),.error(floor1_error));

 vorbis_synthesis synthesis(.clk(clk),.reset(reset),.start(seq_synthesis_start),.long_block(blockflag),
  .previous_short(blockflag&&!previous_window),.next_short(blockflag&&!next_window),.spectral_bins(spectral_bins),
  .workspace_read_valid(synth_read_valid),.workspace_read_ready(workspace_read_ready),
  .workspace_read_address(synth_read_address),.workspace_read_data_valid(workspace_read_data_valid),
  .workspace_read_data(workspace_read_data),.pcm_valid(pcm_valid),.pcm_ready(pcm_ready),.pcm_index(pcm_index),
  .pcm_left(pcm_left),.pcm_right(pcm_right),.ready(synthesis_ready),.done(synthesis_done),.error(synthesis_error));

 assign workspace_read_valid=(phase==5)?coupling_read_valid:(phase==7)?apply0_read_valid:
  (phase==9)?apply1_read_valid:(phase==11)?synth_read_valid:1'b0;
 assign workspace_read_address=(phase==5)?coupling_read_address:(phase==7)?apply0_read_address:
  (phase==9)?apply1_read_address:synth_read_address;
 assign workspace_set_valid=(phase==5)?coupling_set_valid:(phase==7)?apply0_set_valid:
  (phase==9)?apply1_set_valid:1'b0;
 assign workspace_set_address=(phase==5)?coupling_set_address:(phase==7)?apply0_set_address:apply1_set_address;
 assign workspace_set_value=(phase==5)?coupling_set_value:(phase==7)?apply0_set_value:apply1_set_value;
 assign error=sequence_error|bits_error|floor_error|residue_error|coupling_error|floor0_error|floor1_error|synthesis_error|
  (channels!=2)||(mapping_query_submaps!=1);
endmodule
