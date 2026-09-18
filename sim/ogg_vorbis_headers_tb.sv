`timescale 1ns/1ps
module ogg_vorbis_headers_tb;
 reg clk=0,reset=1,byte_valid=0;reg [7:0] byte_data=0;
 wire byte_ready,packet_valid,packet_start,packet_end,packet_ready,header_packet_ready,setup_packet_ready;
 wire bits_packet_ready,bits_valid,packet_buffered_end;wire [31:0] reservoir_bits;wire [6:0] bits_available;
 wire reservoir_audio_start,reservoir_error;reg reservoir_consume=0,reservoir_finish=0;reg [5:0] reservoir_consume_count=0;
 wire [7:0] packet_data;wire [63:0] granule_position;
 wire ogg_error,identification_valid,headers_valid,header_error;
 wire [7:0] channels;wire [31:0] sample_rate;wire [11:0] blocksize_short,blocksize_long;wire [1:0] header_number;
 wire codebooks_valid,codebooks_error;wire [7:0] codebook_count;wire [13:0] active_entries,multiplicand_count;
 wire [6:0] floor_count,residue_count,mapping_count,mode_count;
 wire [63:0] mode_blockflags;wire [511:0] mode_mappings;
 reg [5:0] floor_query=0;reg [4:0] floor_part_query=0;reg [3:0] floor_class_query=0;
 reg [2:0] floor_subbook_query=0;reg [6:0] floor_x_query=0;
 wire [15:0] floor_query_type,floor_query_x;wire [4:0] floor_query_partitions;
 wire [3:0] floor_query_partition_class,floor_query_class_dimensions;
 wire [2:0] floor_query_class_subclasses,floor_query_multiplier;wire [7:0] floor_query_class_masterbook,floor_query_subbook;
 wire [3:0] floor_query_rangebits;
 reg [7:0] codebook_query=0;wire [13:0] active_query_address;
 wire [13:0] codebook_query_start,codebook_query_end;wire [31:0] active_query_entry,active_query_codeword;
 reg [5:0] mapping_query=0;reg [2:0] mapping_submap_query=0;reg mapping_channel_query=0;reg [7:0] mapping_coupling_query=0;
 wire [4:0] mapping_query_submaps;wire [3:0] mapping_query_mux;wire [7:0] mapping_query_floor,mapping_query_residue;
 wire [8:0] mapping_query_coupling_steps;wire mapping_query_magnitude,mapping_query_angle;
 reg [5:0] residue_query=0,residue_class_query=0;reg [2:0] residue_pass_query=0;
 wire [15:0] residue_query_type;wire [23:0] residue_query_begin,residue_query_end,residue_query_partition_size;
 wire [6:0] residue_query_classifications;wire [7:0] residue_query_classbook,residue_query_cascade,residue_query_book;
 reg [13:0] multiplicand_query_address=0;wire [15:0] multiplicand_query_data,codebook_query_dimensions;
 wire [23:0] codebook_query_entries;wire [1:0] codebook_query_lookup_type;wire codebook_query_sequence;
 wire [31:0] codebook_query_minimum,codebook_query_delta;
 wire [13:0] codebook_query_multiplicand_start,codebook_query_multiplicand_count;
 wire audio_header_ready,audio_header_valid,audio_header_error,audio_blockflag;
 wire audio_previous_window,audio_next_window;wire [5:0] audio_mode;wire [7:0] audio_mapping;
 reg huff_start=0,huff_bit_valid=0,huff_bit_data=0;reg [13:0] huff_start_addr=0,huff_end_addr=0;
 wire huff_bit_ready,huff_symbol_valid,huff_error;wire [13:0] huff_table_addr;
 wire [17:0] huff_symbol;wire [5:0] huff_symbol_length;
 wire [31:0] huff_table_entry=codebooks.active_entry_ram.memory[huff_table_addr];
 wire [31:0] huff_table_codeword=codebooks.active_codeword_ram.memory[huff_table_addr];
 wire prefix_leaf_valid;reg prefix_lookup_valid=0;wire [5:0] prefix_leaf_book,prefix_leaf_length;reg [5:0] prefix_lookup_book=0;
 wire [31:0] prefix_leaf_codeword;wire [17:0] prefix_leaf_symbol;reg [7:0] prefix_lookup_bits=0;
 wire prefix_leaf_ready,prefix_result_valid,prefix_hit,prefix_ready,prefix_error;
 wire prefix_builder_done,prefix_builder_error;
 wire [5:0] prefix_result_length;wire [17:0] prefix_result_symbol;
 always #5 clk=~clk;
 ogg_packet_reader ogg(.*,.error(ogg_error));
 wire decoder_gate=packet_bits.packet_number<3||prefix_builder_done;
 assign packet_ready=header_packet_ready&&setup_packet_ready&&audio_header_ready&&bits_packet_ready&&decoder_gate;
 vorbis_header_parser headers(.*,.packet_enable(packet_ready),.packet_ready(header_packet_ready),.error(header_error));
 vorbis_setup_codebooks codebooks(.*,.packet_ready(setup_packet_ready),.valid(codebooks_valid),.error(codebooks_error));
 vorbis_audio_packet_header audio_headers(.clk(clk),.reset(reset),.setup_valid(codebooks_valid),
  .mode_count(mode_count),.mode_blockflags(mode_blockflags),.mode_mappings(mode_mappings),
  .packet_valid(packet_valid&&packet_ready),.packet_data(packet_data),.packet_start(packet_start),.packet_end(packet_end),
  .packet_ready(audio_header_ready),.header_valid(audio_header_valid),.error(audio_header_error),
  .mode(audio_mode),.blockflag(audio_blockflag),.previous_window(audio_previous_window),
  .next_window(audio_next_window),.mapping(audio_mapping));
 vorbis_huffman_decoder huffman(.clk(clk),.reset(reset),.start(huff_start),
  .table_start(huff_start_addr),.table_end(huff_end_addr),.bit_valid(huff_bit_valid),
  .bit_data(huff_bit_data),.bit_ready(huff_bit_ready),.table_address(huff_table_addr),
  .table_entry(huff_table_entry),.table_codeword(huff_table_codeword),
  .symbol_valid(huff_symbol_valid),.symbol_ready(1'b1),.symbol(huff_symbol),
  .symbol_length(huff_symbol_length),.error(huff_error));
 vorbis_huffman_prefix prefix(.clk(clk),.reset(reset),.leaf_valid(prefix_leaf_valid),.leaf_ready(prefix_leaf_ready),
  .leaf_book(prefix_leaf_book),.leaf_codeword(prefix_leaf_codeword),.leaf_length(prefix_leaf_length),
  .leaf_symbol(prefix_leaf_symbol),.lookup_valid(prefix_lookup_valid),.lookup_book(prefix_lookup_book),
  .lookup_bits(prefix_lookup_bits),.lookup_result_valid(prefix_result_valid),.lookup_hit(prefix_hit),
  .lookup_length(prefix_result_length),.lookup_symbol(prefix_result_symbol),.ready(prefix_ready),.error(prefix_error));
 vorbis_prefix_builder prefix_builder(.clk(clk),.reset(reset),.setup_valid(codebooks_valid),.active_entries(active_entries),
  .active_query_address(active_query_address),.active_query_entry(active_query_entry),.active_query_codeword(active_query_codeword),
  .prefix_ready(prefix_ready),.leaf_valid(prefix_leaf_valid),.leaf_ready(prefix_leaf_ready),.leaf_book(prefix_leaf_book),
  .leaf_codeword(prefix_leaf_codeword),.leaf_length(prefix_leaf_length),.leaf_symbol(prefix_leaf_symbol),
  .done(prefix_builder_done),.error(prefix_builder_error));
 vorbis_packet_bits packet_bits(.clk(clk),.reset(reset),.packet_valid(packet_valid&&decoder_gate),.packet_data(packet_data),
  .packet_start(packet_start),.packet_end(packet_end),.packet_ready(bits_packet_ready),
  .audio_packet_start(reservoir_audio_start),.bits_valid(bits_valid),.bits(reservoir_bits),
  .bits_available(bits_available),.consume_valid(reservoir_consume),.consume_count(reservoir_consume_count),
  .packet_buffered_end(packet_buffered_end),.finish_packet(reservoir_finish),.error(reservoir_error));
 integer fd,value,packets=0,bytes=0,input_bytes=0,hash_index;
 reg [31:0] codeword_hash;
 reg [31:0] floor_setup_hash;
 reg [31:0] residue_setup_hash;
 integer residue_i,residue_class_i,residue_pass_i;
 integer floor_i,floor_part,floor_class,floor_book,floor_x,floor_max_class,floor_total_x;
 integer cycles=0;
 reg setup_error_seen=0;
 reg setup_valid_seen=0;
 reg [6:0] previous_setup_state=0;
 reg [23:0] previous_order_number=0;reg [5:0] previous_need_bits=0;
 integer audio_headers_seen=0,short_blocks=0,long_blocks=0,prefix_entries=0;
 integer source_audio_bytes=0,reservoir_audio_bytes=0,reservoir_packets=0;
 reg [31:0] source_audio_hash=32'h811c9dc5,reservoir_audio_hash=32'h811c9dc5;
 task decode_table_entry;input integer table_index;input integer book;integer bit_index;reg [31:0] word;reg [5:0] word_length;reg [17:0] expected;begin
  huff_start_addr=codebooks.book_descriptor_ram.memory[book][122:109];
  huff_end_addr=huff_start_addr+codebooks.book_descriptor_ram.memory[book][108:95];
  word=codebooks.active_codeword_ram.memory[table_index];word_length=codebooks.active_entry_ram.memory[table_index][5:0];
  expected=codebooks.active_entry_ram.memory[table_index][23:6];
  @(negedge clk);huff_start=1;@(negedge clk);huff_start=0;
  for(bit_index=0;bit_index<word_length;bit_index=bit_index+1)begin
   while(!huff_bit_ready)@(negedge clk);
   huff_bit_data=word[bit_index];huff_bit_valid=1;@(negedge clk);huff_bit_valid=0;
  end
  while(!huff_symbol_valid&&!huff_error)@(negedge clk);
  if(huff_error||huff_symbol!=expected||huff_symbol_length!=word_length)
   $fatal(1,"Huffman decode index=%0d got=%0d/%0d expected=%0d/%0d",table_index,huff_symbol,huff_symbol_length,expected,word_length);
  @(negedge clk);
 end endtask
 task lookup_prefix_entry;input integer table_index;reg [7:0] bits;begin
  bits=codebooks.active_codeword_ram.memory[table_index][7:0];
  @(negedge clk);prefix_lookup_book=codebooks.active_entry_ram.memory[table_index][29:24];prefix_lookup_bits=bits;prefix_lookup_valid=1;
  @(negedge clk);prefix_lookup_valid=0;
  while(!prefix_result_valid)@(negedge clk);
  if(!prefix_hit||prefix_result_length!=codebooks.active_entry_ram.memory[table_index][5:0]||
     prefix_result_symbol!=codebooks.active_entry_ram.memory[table_index][23:6])
   $fatal(1,"prefix lookup index=%0d hit=%0d got=%0d/%0d",table_index,prefix_hit,prefix_result_symbol,prefix_result_length);
 end endtask
 always @(posedge clk)begin
  cycles<=cycles+1;
  previous_setup_state<=codebooks.state;
  previous_order_number<=codebooks.order_number;previous_need_bits<=codebooks.need_bits;
  if(codebooks.valid&&!setup_valid_seen)begin
   setup_valid_seen<=1;
   $display("SETUP_VALID books=%0d active=%0d mult=%0d floors=%0d residues=%0d mappings=%0d modes=%0d input=%0d",
    codebook_count,active_entries,multiplicand_count,floor_count,residue_count,mapping_count,mode_count,input_bytes);
  end
  if(codebooks.error&&!setup_error_seen)begin
   setup_error_seen<=1;
   $display("SETUP_ERROR state=%0d previous=%0d order=%0d need=%0d field=%h book=%0d entry=%0d/%0d active=%0d length=%0d marker=%h marker3=%h",
    codebooks.state,previous_setup_state,previous_order_number,previous_need_bits,codebooks.field,codebooks.book_index,codebooks.local_entry,codebooks.entries,
    codebooks.active_entries,codebooks.save_length,codebooks.code_marker[codebooks.save_length],codebooks.code_marker[3]);
  end
  if(cycles==5000000)$fatal(1,"watchdog input=%0d state=%0d bits=%0d need=%0d error=%0d valid=%0d book=%0d entry=%0d/%0d active=%0d mult=%0d run=%0d len=%0d floor=%0d residue=%0d map=%0d mode=%0d",
   input_bytes,codebooks.state,codebooks.bit_count,codebooks.need_bits,codebooks.error,codebooks.valid,
   codebooks.book_index,codebooks.local_entry,codebooks.entries,codebooks.active_entries,codebooks.multiplicand_count,
   codebooks.run_remaining,codebooks.current_length,floor_count,residue_count,mapping_count,mode_count);
 end
 always @(posedge clk)if(audio_header_valid)begin
  audio_headers_seen<=audio_headers_seen+1;
  if(audio_blockflag)long_blocks<=long_blocks+1;else short_blocks<=short_blocks+1;
 end
 always @(posedge clk)if(packet_valid&&packet_ready)begin
  bytes<=bytes+1;if(packet_start)packets<=packets+1;
  if(packet_bits.packet_number==3)begin source_audio_bytes<=source_audio_bytes+1;source_audio_hash<=(source_audio_hash^packet_data)*32'h01000193;end
 end
 always @(negedge clk)begin
  reservoir_consume=0;reservoir_finish=0;reservoir_consume_count=0;
  if(bits_valid&&bits_available>=8)begin
   reservoir_consume=1;reservoir_consume_count=8;reservoir_audio_bytes=reservoir_audio_bytes+1;
   reservoir_audio_hash=(reservoir_audio_hash^reservoir_bits[7:0])*32'h01000193;
  end else if(packet_buffered_end)reservoir_finish=1;
  if(reservoir_audio_start)reservoir_packets=reservoir_packets+1;
 end
 always @(posedge clk)if(byte_valid&&byte_ready)input_bytes<=input_bytes+1;
 initial begin
  repeat(4)@(posedge clk);reset=0;
  fd=$fopen("/tmp/mister_mp3_vorbis_test.ogg","rb");if(!fd)$fatal(1,"fixture open failed");
  while(!$feof(fd))begin
   value=$fgetc(fd);if(value>=0)begin
    @(negedge clk);byte_data=value[7:0];byte_valid=1;
    while(!byte_ready)@(negedge clk);
   end
  end
  @(negedge clk);byte_valid=0;$fclose(fd);repeat(20)@(posedge clk);
  if(ogg_error)$fatal(1,"Ogg parser error input=%0d payload=%0d",input_bytes,bytes);
  if(header_error)$fatal(1,"Vorbis header error number=%0d index=%0d id=%0d valid=%0d profile=%0d/%0d blocks=%0d/%0d",
   header_number,headers.index,identification_valid,headers_valid,channels,sample_rate,blocksize_short,blocksize_long);
  if(!headers_valid)$fatal(1,"headers never completed ready=%0d/%0d/%0d pv=%0d header=%0d index=%0d setup packet=%0d active=%0d target=%0d hbytes=%0d state=%0d book=%0d valid=%0d error=%0d bits=%0d",
   packet_ready,header_packet_ready,setup_packet_ready,packet_valid,
   header_number,headers.index,codebooks.packet_number,codebooks.setup_packet,codebooks.setup_target,codebooks.header_bytes,
   codebooks.state,codebooks.book_index,codebooks_valid,codebooks_error,codebooks.bit_count);
  if(codebooks_error||!codebooks_valid)$fatal(1,"setup failed state=%0d book=%0d bits=%0d floors=%0d floor_i=%0d residues=%0d residue_i=%0d class=%0d/%0d pass=%0d cascade=%x mappings=%0d modes=%0d",
   codebooks.state,codebooks.book_index,codebooks.bit_count,floor_count,codebooks.item_index,residue_count,
   codebooks.item_index,codebooks.residue_class_index,codebooks.residue_classifications,codebooks.residue_pass,
   codebooks.residue_cascade[codebooks.residue_class_index],mapping_count,mode_count);
  if(audio_header_error)$fatal(1,"audio packet header error after %0d packets",audio_headers_seen);
  if(reservoir_error)$fatal(1,"audio packet reservoir error reason=%0d active=%0d end=%0d bits=%0d",
   packet_bits.error_reason,packet_bits.audio_active,packet_buffered_end,bits_available);
  if(reservoir_packets!=audio_headers_seen||reservoir_audio_bytes!=source_audio_bytes||reservoir_audio_hash!=source_audio_hash)
   $fatal(1,"reservoir packets=%0d/%0d bytes=%0d/%0d hash=%x/%x",reservoir_packets,audio_headers_seen,
    reservoir_audio_bytes,source_audio_bytes,reservoir_audio_hash,source_audio_hash);
  if(audio_headers_seen!=packets-3)$fatal(1,"audio headers=%0d packets=%0d",audio_headers_seen,packets);
  if(codebook_count!=42||active_entries!=3643||multiplicand_count!=133)
   $fatal(1,"codebooks=%0d active=%0d multiplicands=%0d",codebook_count,active_entries,multiplicand_count);
  codeword_hash=32'h811c9dc5;
  for(hash_index=0;hash_index<active_entries;hash_index=hash_index+1)begin
   if(codebooks.active_entry_ram.memory[hash_index][5:0]<=8)prefix_entries=prefix_entries+1;
   codeword_hash=(codeword_hash^codebooks.active_entry_ram.memory[hash_index][31:24])*32'h01000193;
   codeword_hash=(codeword_hash^codebooks.active_entry_ram.memory[hash_index][23:6])*32'h01000193;
   codeword_hash=(codeword_hash^codebooks.active_entry_ram.memory[hash_index][5:0])*32'h01000193;
   codeword_hash=(codeword_hash^codebooks.active_codeword_ram.memory[hash_index])*32'h01000193;
  end
  if(codeword_hash!=32'h110472f2)$fatal(1,"codeword table hash=%x",codeword_hash);
  if(floor_count!=2||residue_count!=2||mapping_count!=2||mode_count!=2)
   $fatal(1,"setup tables floors=%0d residues=%0d mappings=%0d modes=%0d",
    floor_count,residue_count,mapping_count,mode_count);
  floor_setup_hash=32'h811c9dc5;
  for(floor_i=0;floor_i<floor_count;floor_i=floor_i+1)begin
   floor_setup_hash=(floor_setup_hash^codebooks.floor_type_mem.memory[floor_i])*32'h01000193;
   floor_setup_hash=(floor_setup_hash^codebooks.floor1_partitions_mem.memory[floor_i])*32'h01000193;
   floor_max_class=0;floor_total_x=0;
   for(floor_part=0;floor_part<codebooks.floor1_partitions_mem.memory[floor_i];floor_part=floor_part+1)begin
    floor_class=codebooks.floor1_partition_class_mem.memory[floor_i*32+floor_part];
    floor_setup_hash=(floor_setup_hash^floor_class)*32'h01000193;
    if(floor_class>floor_max_class)floor_max_class=floor_class;
    floor_total_x=floor_total_x+codebooks.floor1_class_dimensions_mem.memory[floor_i*16+floor_class];
   end
   for(floor_class=0;floor_class<=floor_max_class;floor_class=floor_class+1)begin
    floor_setup_hash=(floor_setup_hash^codebooks.floor1_class_dimensions_mem.memory[floor_i*16+floor_class])*32'h01000193;
    floor_setup_hash=(floor_setup_hash^codebooks.floor1_class_subclasses_mem.memory[floor_i*16+floor_class])*32'h01000193;
    floor_setup_hash=(floor_setup_hash^codebooks.floor1_class_masterbook_mem.memory[floor_i*16+floor_class])*32'h01000193;
    for(floor_book=0;floor_book<(1<<codebooks.floor1_class_subclasses_mem.memory[floor_i*16+floor_class]);floor_book=floor_book+1)
     floor_setup_hash=(floor_setup_hash^codebooks.floor_subbook_ram.memory[floor_i*128+floor_class*8+floor_book])*32'h01000193;
   end
   floor_setup_hash=(floor_setup_hash^codebooks.floor1_multiplier_mem.memory[floor_i])*32'h01000193;
   floor_setup_hash=(floor_setup_hash^codebooks.floor1_rangebits_mem.memory[floor_i])*32'h01000193;
   for(floor_x=0;floor_x<floor_total_x+2;floor_x=floor_x+1)
    floor_setup_hash=(floor_setup_hash^codebooks.floor_x_ram.memory[floor_i*65+floor_x])*32'h01000193;
  end
  if(floor_setup_hash!=32'h18e84fe4)$fatal(1,"Floor-1 setup hash=%x",floor_setup_hash);
  residue_setup_hash=32'h811c9dc5;
  for(residue_i=0;residue_i<residue_count;residue_i=residue_i+1)begin
   residue_setup_hash=(residue_setup_hash^codebooks.residue_type_mem.memory[residue_i])*32'h01000193;
   residue_setup_hash=(residue_setup_hash^codebooks.residue_begin_mem.memory[residue_i])*32'h01000193;
   residue_setup_hash=(residue_setup_hash^codebooks.residue_end_mem.memory[residue_i])*32'h01000193;
   residue_setup_hash=(residue_setup_hash^codebooks.residue_partition_size_mem.memory[residue_i])*32'h01000193;
   residue_setup_hash=(residue_setup_hash^codebooks.residue_classifications_mem.memory[residue_i])*32'h01000193;
   residue_setup_hash=(residue_setup_hash^codebooks.residue_classbook_mem.memory[residue_i])*32'h01000193;
   for(residue_class_i=0;residue_class_i<codebooks.residue_classifications_mem.memory[residue_i];residue_class_i=residue_class_i+1)
    residue_setup_hash=(residue_setup_hash^codebooks.cascade_ram.memory[residue_i*64+residue_class_i])*32'h01000193;
   for(residue_class_i=0;residue_class_i<codebooks.residue_classifications_mem.memory[residue_i];residue_class_i=residue_class_i+1)
    for(residue_pass_i=0;residue_pass_i<8;residue_pass_i=residue_pass_i+1)
     residue_setup_hash=(residue_setup_hash^codebooks.residue_book_ram.memory[residue_i*512+residue_class_i*8+residue_pass_i])*32'h01000193;
  end
  if(residue_setup_hash!=32'h5c234e23)$fatal(1,"residue setup hash=%x",residue_setup_hash);
  if(mode_blockflags[1:0]!=2'b10||mode_mappings[7:0]!=0||mode_mappings[15:8]!=1)
   $fatal(1,"mode table flags=%b mappings=%0d/%0d",mode_blockflags[1:0],mode_mappings[7:0],mode_mappings[15:8]);
  if(codebooks.mapping_submaps_mem.memory[0]!=1||codebooks.mapping_submaps_mem.memory[1]!=1||
     codebooks.mapping_floor_mem.memory[0]!=0||codebooks.mapping_residue_mem.memory[0]!=0||
     codebooks.mapping_floor_mem.memory[8]!=1||codebooks.mapping_residue_mem.memory[8]!=1||
     codebooks.mapping_coupling_steps_mem.memory[0]!=1||codebooks.mapping_coupling_steps_mem.memory[1]!=1||
     codebooks.magnitude_ram.memory[0]!=0||codebooks.angle_ram.memory[0]!=1||
     codebooks.magnitude_ram.memory[256]!=0||codebooks.angle_ram.memory[256]!=1)
   $fatal(1,"mapping setup mismatch submaps=%0d/%0d floor=%0d/%0d residue=%0d/%0d coupling=%0d/%0d pairs=%0d:%0d/%0d:%0d",
    codebooks.mapping_submaps_mem.memory[0],codebooks.mapping_submaps_mem.memory[1],codebooks.mapping_floor_mem.memory[0],codebooks.mapping_floor_mem.memory[8],
    codebooks.mapping_residue_mem.memory[0],codebooks.mapping_residue_mem.memory[8],codebooks.mapping_coupling_steps_mem.memory[0],
    codebooks.mapping_coupling_steps_mem.memory[1],codebooks.magnitude_ram.memory[0],codebooks.angle_ram.memory[0],
    codebooks.magnitude_ram.memory[256],codebooks.angle_ram.memory[256]);
  decode_table_entry(0,0);decode_table_entry(5,0);
  decode_table_entry(codebooks.book_descriptor_ram.memory[1][122:109]-1,0);
  decode_table_entry(active_entries-1,codebook_count-1);
  if(!prefix_builder_done||prefix_builder_error||prefix_error)$fatal(1,"automatic prefix construction failed done=%0d builder=%0d cache=%0d",
   prefix_builder_done,prefix_builder_error,prefix_error);
  lookup_prefix_entry(0);lookup_prefix_entry(5);lookup_prefix_entry(active_entries-1);
  if(channels!=2||sample_rate!=44100)$fatal(1,"profile %0dch %0dHz",channels,sample_rate);
  if(blocksize_short!=256||blocksize_long!=2048)$fatal(1,"blocks %0d/%0d",blocksize_short,blocksize_long);
  if(packets<3)$fatal(1,"only %0d packets",packets);
  $display("PASS packets=%0d audio=%0d short=%0d long=%0d bytes=%0d profile=%0dch/%0dHz blocks=%0d/%0d books=%0d active=%0d prefix=%0d multiplicands=%0d floors=%0d residues=%0d mappings=%0d modes=%0d",
   packets,audio_headers_seen,short_blocks,long_blocks,
   bytes,channels,sample_rate,blocksize_short,blocksize_long,codebook_count,active_entries,prefix_entries,multiplicand_count,
   floor_count,residue_count,mapping_count,mode_count);
  $finish;
 end
endmodule
