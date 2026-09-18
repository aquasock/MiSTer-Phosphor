// One-time Vorbis setup-header codebook reader. Bit fields are consumed LSB
// first directly from the Ogg packet stream. Only active sparse entries are
// retained, which bounds real storage by Huffman leaves rather than by large
// mostly-empty declared vector spaces.
module vorbis_setup_codebooks(
 input wire clk,input wire reset,
 input wire [7:0] channels,
 input wire packet_valid,input wire [7:0] packet_data,
 input wire packet_start,input wire packet_end,output wire packet_ready,
 output reg valid=0,output reg error=0,output reg [7:0] codebook_count=0,
 output reg [13:0] active_entries=0,output reg [13:0] multiplicand_count=0,
 output reg [6:0] floor_count=0,output reg [6:0] residue_count=0,
 output reg [6:0] mapping_count=0,output reg [6:0] mode_count=0,
 output reg [63:0] mode_blockflags=0,
 output reg [511:0] mode_mappings=0,
 input wire [5:0] floor_query,input wire [4:0] floor_part_query,
 input wire [3:0] floor_class_query,input wire [2:0] floor_subbook_query,
 input wire [6:0] floor_x_query,
 output wire [15:0] floor_query_type,output wire [4:0] floor_query_partitions,
 output wire [3:0] floor_query_partition_class,
 output wire [3:0] floor_query_class_dimensions,output wire [2:0] floor_query_class_subclasses,
 output wire [7:0] floor_query_class_masterbook,output wire [7:0] floor_query_subbook,
 output wire [2:0] floor_query_multiplier,output wire [3:0] floor_query_rangebits,
 output wire [15:0] floor_query_x,
 input wire [7:0] codebook_query,input wire [13:0] active_query_address,
 output wire [13:0] codebook_query_start,output wire [13:0] codebook_query_end,
 output wire [31:0] active_query_entry,output wire [31:0] active_query_codeword,
 input wire [5:0] mapping_query,input wire [2:0] mapping_submap_query,
 input wire mapping_channel_query,input wire [7:0] mapping_coupling_query,
 output wire [4:0] mapping_query_submaps,output reg [3:0] mapping_query_mux,
 output wire [7:0] mapping_query_floor,output wire [7:0] mapping_query_residue,
 output wire [8:0] mapping_query_coupling_steps,
 output wire mapping_query_magnitude,output wire mapping_query_angle,
 input wire [5:0] residue_query,input wire [5:0] residue_class_query,input wire [2:0] residue_pass_query,
 output wire [15:0] residue_query_type,output wire [23:0] residue_query_begin,
 output wire [23:0] residue_query_end,output wire [23:0] residue_query_partition_size,
 output wire [6:0] residue_query_classifications,output wire [7:0] residue_query_classbook,
 output wire [7:0] residue_query_cascade,output wire [7:0] residue_query_book,
 input wire [13:0] multiplicand_query_address,output wire [15:0] multiplicand_query_data,
 output wire [15:0] codebook_query_dimensions,output wire [23:0] codebook_query_entries,
 output wire [1:0] codebook_query_lookup_type,output wire codebook_query_sequence,
 output wire [31:0] codebook_query_minimum,output wire [31:0] codebook_query_delta,
 output wire [13:0] codebook_query_multiplicand_start,output wire [13:0] codebook_query_multiplicand_count
);
 localparam S_COUNT=0,S_SYNC=1,S_DIM=2,S_ENTRIES=3,S_ORDERED=4,S_SPARSE=5,
  S_LENGTH=6,S_PRESENT=7,S_ORDER_LENGTH=8,S_ORDER_NUMBER=9,S_ORDER_WRITE=10,
  S_LOOKUP=11,S_MIN=12,S_DELTA=13,S_VALUE_BITS=14,S_SEQUENCE=15,
  S_CALC_INIT=16,S_CALC_POWER=17,S_MULTIPLICAND=18,S_NEXT_BOOK=19,
  S_TIME_COUNT=20,S_TIME_TYPE=21,S_FLOOR_COUNT=22,S_FLOOR_TYPE=23,
  S_F0_ORDER=24,S_F0_RATE=25,S_F0_BARK=26,S_F0_AMPBITS=27,S_F0_AMPOFF=28,S_F0_BOOKS=29,S_F0_BOOK=30,
  S_F1_PARTS=31,S_F1_PART_CLASS=32,S_F1_CLASS_DIM=33,S_F1_CLASS_SUB=34,S_F1_MASTER=35,S_F1_SUBBOOK=36,
  S_F1_MULT=37,S_F1_RANGE=38,S_F1_X=39,S_NEXT_FLOOR=40,
  S_RES_COUNT=41,S_RES_TYPE=42,S_RES_BEGIN=43,S_RES_END=44,S_RES_PART=45,S_RES_CLASSES=46,S_RES_CLASSBOOK=47,
  S_RES_LOW=48,S_RES_FLAG=49,S_RES_HIGH=50,S_RES_BOOK=51,S_NEXT_RES=52,
  S_MAP_COUNT=53,S_MAP_TYPE=54,S_MAP_SUBFLAG=55,S_MAP_SUBCOUNT=56,S_MAP_COUPLEFLAG=57,S_MAP_COUPLECOUNT=58,
  S_MAP_MAG=59,S_MAP_ANGLE=60,S_MAP_RESERVED=61,S_MAP_MUX=62,S_MAP_TIME=63,S_MAP_FLOOR=64,S_MAP_RES=65,S_NEXT_MAP=66,
  S_MODE_COUNT=67,S_MODE_BLOCK=68,S_MODE_WINDOW=69,S_MODE_TRANSFORM=70,S_MODE_MAPPING=71,S_FRAMING=72,S_DONE=73,
  S_RES_CHECK=74,S_SAVE_DOWN=75,S_SAVE_UP=76,S_SAVE_REVERSE=77,S_SAVE_COMMIT=78,S_F1_X_INIT=79,
  S_F1_TOTAL_ACCUM=80;
 reg [6:0] state=S_COUNT;
 wire consume;
 reg [1:0] packet_number=0;
 reg [3:0] header_bytes=0;
 reg setup_packet=0,setup_ended=0;
 reg [63:0] reservoir=0;
 reg [6:0] bit_count=0;
 reg [7:0] book_index=0;
 reg [15:0] dimensions=0;
 reg [23:0] entries=0,local_entry=0;
 reg ordered=0,sparse=0,present=0;
 reg [5:0] current_length=0;
 reg [23:0] run_remaining=0;
 reg [3:0] lookup_type=0;
 reg [4:0] value_bits=0;
 reg [23:0] values_remaining=0;
 reg [23:0] calc_candidate=0,calc_exp=0;
 reg [47:0] calc_power=0;
 reg [13:0] book_active_start_current=0,book_multiplicand_start_current=0;
 reg [31:0] minimum_value_current=0,delta_value_current=0;
 reg sequence_current=0;
 reg [31:0] code_marker[1:32];
 reg [5:0] save_length=0,save_index=0,save_reverse_index=0;
 reg [31:0] save_assigned=0,save_branch=0,save_reversed=0;
 reg save_from_ordered=0;
 reg [6:0] item_index=0;
 reg [6:0] time_count=0;
 reg [4:0] floor1_partitions=0,part_index=0;
 reg [3:0] floor1_partition_class[0:31];
 reg [3:0] floor1_max_class=0,class_index=0;
 reg [3:0] floor1_class_dimensions[0:15];
 reg [2:0] floor1_class_subclasses[0:15];
 reg [4:0] subbook_remaining=0;
 reg [8:0] floor1_x_remaining=0;
 reg [8:0] floor1_x_total=0;
 reg [6:0] floor1_x_write=0;
 reg [2:0] floor1_subbook_index=0;
 wire [162:0] book_descriptor_read;
 wire [13:0] book_active_count_current=active_entries-book_active_start_current;
 wire [13:0] book_multiplicand_count_current=multiplicand_count-book_multiplicand_start_current;
 wire [162:0] book_descriptor_write_data={dimensions,entries,book_active_start_current,
  book_active_count_current,book_multiplicand_start_current,book_multiplicand_count_current,
  lookup_type[1:0],sequence_current,minimum_value_current,delta_value_current};
 vorbis_setup_ram #(.WIDTH(163),.DEPTH(256),.ADDR_WIDTH(8)) book_descriptor_ram(clk,
  state==S_NEXT_BOOK,book_index,book_descriptor_write_data,codebook_query,book_descriptor_read);
 assign codebook_query_dimensions=book_descriptor_read[162:147];
 assign codebook_query_entries=book_descriptor_read[146:123];
 assign codebook_query_start=book_descriptor_read[122:109];
 assign codebook_query_end=book_descriptor_read[122:109]+book_descriptor_read[108:95];
 assign codebook_query_multiplicand_start=book_descriptor_read[94:81];
 assign codebook_query_multiplicand_count=book_descriptor_read[80:67];
 assign codebook_query_lookup_type=book_descriptor_read[66:65];
 assign codebook_query_sequence=book_descriptor_read[64];
 assign codebook_query_minimum=book_descriptor_read[63:32];
 assign codebook_query_delta=book_descriptor_read[31:0];
 wire active_write=state==S_SAVE_COMMIT;
 wire multiplicand_write=consume&&state==S_MULTIPLICAND;
 // `field` exposes the next 32 reservoir bits, not only the requested field.
 // Mask lookup multiplicands to value_bits before storing them or adjacent
 // setup bits become part of every decoded residue vector value.
 wire [15:0] multiplicand_write_data=field[15:0]&(16'hffff>>(16-value_bits));
 wire floor_x_write_enable=(consume&&state==S_F1_RANGE)||state==S_F1_X_INIT||(consume&&state==S_F1_X);
 wire [9:0] floor_x_write_address=state==S_F1_RANGE?item_index*65:state==S_F1_X_INIT?item_index*65+1:item_index*65+floor1_x_write;
 wire [9:0] floor_x_read_address=floor_query*65+floor_x_query;
 wire [15:0] floor_x_write_data=state==S_F1_RANGE?0:state==S_F1_X_INIT?(16'd1<<coupling_bits):(field[15:0]&((16'd1<<coupling_bits)-1'b1));
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(8192),.ADDR_WIDTH(14)) active_entry_ram(clk,active_write,active_entries,{book_index,local_entry[17:0],save_length},active_query_address,active_query_entry);
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(8192),.ADDR_WIDTH(14)) active_codeword_ram(clk,active_write,active_entries,save_reversed,active_query_address,active_query_codeword);
 vorbis_setup_ram #(.WIDTH(16),.DEPTH(8192),.ADDR_WIDTH(14)) multiplicand_ram(clk,multiplicand_write,multiplicand_count,multiplicand_write_data,multiplicand_query_address,multiplicand_query_data);
 vorbis_setup_ram #(.WIDTH(16),.DEPTH(520),.ADDR_WIDTH(10)) floor_x_ram(clk,floor_x_write_enable,floor_x_write_address,floor_x_write_data,floor_x_read_address,floor_query_x);
 wire [9:0] floor_subbook_write_address=item_index*128+class_index*8+floor1_subbook_index;
 wire [9:0] floor_subbook_read_address=floor_query*128+floor_class_query*8+floor_subbook_query;
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(1024),.ADDR_WIDTH(10)) floor_subbook_ram(clk,
  consume&&state==S_F1_SUBBOOK,floor_subbook_write_address,field[7:0]==0?8'hff:field[7:0]-1'b1,
  floor_subbook_read_address,floor_query_subbook);
 wire [7:0] floor_partition_read_address=floor_query*32+floor_part_query;
 wire [6:0] floor_class_read_address=floor_query*16+floor_class_query;
 vorbis_setup_ram #(.WIDTH(16),.DEPTH(64),.ADDR_WIDTH(6)) floor_type_mem(clk,
  consume&&state==S_FLOOR_TYPE,item_index[5:0],field[15:0],floor_query,floor_query_type);
 vorbis_setup_ram #(.WIDTH(5),.DEPTH(64),.ADDR_WIDTH(6)) floor1_partitions_mem(clk,
  consume&&state==S_F1_PARTS,item_index[5:0],field[4:0],floor_query,floor_query_partitions);
 vorbis_setup_ram #(.WIDTH(4),.DEPTH(256),.ADDR_WIDTH(8)) floor1_partition_class_mem(clk,
  consume&&state==S_F1_PART_CLASS,{item_index[2:0],part_index},field[3:0],
  floor_partition_read_address,floor_query_partition_class);
 vorbis_setup_ram #(.WIDTH(4),.DEPTH(128),.ADDR_WIDTH(7)) floor1_class_dimensions_mem(clk,
  consume&&state==S_F1_CLASS_DIM,{item_index[2:0],class_index},{1'b0,field[2:0]}+4'd1,
  floor_class_read_address,floor_query_class_dimensions);
 vorbis_setup_ram #(.WIDTH(3),.DEPTH(128),.ADDR_WIDTH(7)) floor1_class_subclasses_mem(clk,
  consume&&state==S_F1_CLASS_SUB,{item_index[2:0],class_index},{1'b0,field[1:0]},
  floor_class_read_address,floor_query_class_subclasses);
 wire floor_master_write=consume&&(state==S_F1_MASTER||(state==S_F1_CLASS_SUB&&field[1:0]==0));
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(128),.ADDR_WIDTH(7)) floor1_class_masterbook_mem(clk,
  floor_master_write,{item_index[2:0],class_index},state==S_F1_MASTER?field[7:0]:8'hff,
  floor_class_read_address,floor_query_class_masterbook);
 vorbis_setup_ram #(.WIDTH(3),.DEPTH(64),.ADDR_WIDTH(6)) floor1_multiplier_mem(clk,
  consume&&state==S_F1_MULT,item_index[5:0],{1'b0,field[1:0]}+3'd1,floor_query,floor_query_multiplier);
 vorbis_setup_ram #(.WIDTH(4),.DEPTH(64),.ADDR_WIDTH(6)) floor1_rangebits_mem(clk,
  consume&&state==S_F1_RANGE,item_index[5:0],field[3:0],floor_query,floor_query_rangebits);
 reg [6:0] residue_classifications=0,residue_class_index=0;
 reg [7:0] residue_cascade[0:63];
 reg [2:0] residue_pass=0;
 reg [4:0] map_submaps=0,map_index=0;
 reg [8:0] coupling_remaining=0;
 reg [8:0] coupling_index=0;
 reg [7:0] channel_index=0;
 reg [6:0] coupling_bits=0;
 reg [7:0] mode_index=0;
 reg [3:0] mapping_mux_mem[0:127];
 wire cascade_write=consume&&(state==S_RES_HIGH||(state==S_RES_FLAG&&!field[0]));
 wire [8:0] cascade_write_address=item_index*64+residue_class_index;
 wire [7:0] cascade_write_data=state==S_RES_HIGH?{field[4:0],residue_cascade[residue_class_index][2:0]}:
  {5'd0,residue_cascade[residue_class_index][2:0]};
 wire [8:0] cascade_read_address=residue_query*64+residue_class_query;
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(512),.ADDR_WIDTH(9)) cascade_ram(clk,cascade_write,
  cascade_write_address,cascade_write_data,cascade_read_address,residue_query_cascade);
 wire residue_book_write=(consume&&state==S_RES_BOOK)||
  (!consume&&state==S_RES_CHECK&&!residue_cascade[residue_class_index][residue_pass]);
 wire [11:0] residue_book_write_address=item_index*512+residue_class_index*8+residue_pass;
 wire [11:0] residue_book_read_address=residue_query*512+residue_class_query*8+residue_pass_query;
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(4096),.ADDR_WIDTH(12)) residue_book_ram(clk,residue_book_write,
  residue_book_write_address,state==S_RES_BOOK?field[7:0]:8'hff,residue_book_read_address,residue_query_book);
 vorbis_setup_ram #(.WIDTH(16),.DEPTH(64),.ADDR_WIDTH(6)) residue_type_mem(clk,
  consume&&state==S_RES_TYPE,item_index[5:0],field[15:0],residue_query,residue_query_type);
 vorbis_setup_ram #(.WIDTH(24),.DEPTH(64),.ADDR_WIDTH(6)) residue_begin_mem(clk,
  consume&&state==S_RES_BEGIN,item_index[5:0],field[23:0],residue_query,residue_query_begin);
 vorbis_setup_ram #(.WIDTH(24),.DEPTH(64),.ADDR_WIDTH(6)) residue_end_mem(clk,
  consume&&state==S_RES_END,item_index[5:0],field[23:0],residue_query,residue_query_end);
 vorbis_setup_ram #(.WIDTH(24),.DEPTH(64),.ADDR_WIDTH(6)) residue_partition_size_mem(clk,
  consume&&state==S_RES_PART,item_index[5:0],field[23:0]+1'b1,residue_query,residue_query_partition_size);
 vorbis_setup_ram #(.WIDTH(7),.DEPTH(64),.ADDR_WIDTH(6)) residue_classifications_mem(clk,
  consume&&state==S_RES_CLASSES,item_index[5:0],{1'b0,field[5:0]}+7'd1,residue_query,residue_query_classifications);
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(64),.ADDR_WIDTH(6)) residue_classbook_mem(clk,
  consume&&state==S_RES_CLASSBOOK,item_index[5:0],field[7:0],residue_query,residue_query_classbook);
 wire [10:0] coupling_write_address=item_index*256+coupling_index;
 wire [10:0] coupling_read_address=mapping_query*256+mapping_coupling_query;
 vorbis_setup_ram #(.WIDTH(1),.DEPTH(2048),.ADDR_WIDTH(11)) magnitude_ram(clk,
  consume&&state==S_MAP_MAG,coupling_write_address,field[0],coupling_read_address,mapping_query_magnitude);
 vorbis_setup_ram #(.WIDTH(1),.DEPTH(2048),.ADDR_WIDTH(11)) angle_ram(clk,
  consume&&state==S_MAP_ANGLE,coupling_write_address,field[0],coupling_read_address,mapping_query_angle);
 wire mapping_submaps_write=consume&&(state==S_MAP_SUBCOUNT||(state==S_MAP_SUBFLAG&&!field[0]));
 wire mapping_coupling_write=consume&&(state==S_MAP_COUPLECOUNT||(state==S_MAP_COUPLEFLAG&&!field[0]));
 wire [8:0] mapping_coupling_write_data=state==S_MAP_COUPLECOUNT?field[7:0]+1'b1:9'd0;
 wire [5:0] mapping_submap_read_address={mapping_query[2:0],mapping_submap_query};
 vorbis_setup_ram #(.WIDTH(5),.DEPTH(64),.ADDR_WIDTH(6)) mapping_submaps_mem(clk,
  mapping_submaps_write,item_index[5:0],state==S_MAP_SUBCOUNT?field[3:0]+1'b1:5'd1,
  mapping_query,mapping_query_submaps);
 vorbis_setup_ram #(.WIDTH(9),.DEPTH(64),.ADDR_WIDTH(6)) mapping_coupling_steps_mem(clk,
  mapping_coupling_write,item_index[5:0],mapping_coupling_write_data,
  mapping_query,mapping_query_coupling_steps);
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(64),.ADDR_WIDTH(6)) mapping_floor_mem(clk,
  consume&&state==S_MAP_FLOOR,{item_index[2:0],map_index[2:0]},field[7:0],
  mapping_submap_read_address,mapping_query_floor);
 vorbis_setup_ram #(.WIDTH(8),.DEPTH(64),.ADDR_WIDTH(6)) mapping_residue_mem(clk,
  consume&&state==S_MAP_RES,{item_index[2:0],map_index[2:0]},field[7:0],
  mapping_submap_read_address,mapping_query_residue);
 always @(posedge clk)begin
  mapping_query_mux<=mapping_mux_mem[mapping_query*2+mapping_channel_query];
 end

 function [5:0] ilog24;input [23:0] value;integer i;begin
  ilog24=0;for(i=0;i<24;i=i+1)if(value[i])ilog24=i+1;
 end endfunction
 function [5:0] ilog8;input [7:0] value;integer i;begin
  ilog8=0;for(i=0;i<8;i=i+1)if(value[i])ilog8=i+1;
 end endfunction
 integer loop_i;
 reg [5:0] need_bits=8;
 always @* begin
  case(state)
   S_COUNT:need_bits=8;S_SYNC:need_bits=24;S_DIM:need_bits=16;S_ENTRIES:need_bits=24;
   S_ORDERED,S_SPARSE,S_PRESENT,S_SEQUENCE:need_bits=1;
   S_LENGTH,S_ORDER_LENGTH:need_bits=5;
   S_ORDER_NUMBER:need_bits=ilog24(entries-local_entry);
   S_LOOKUP:need_bits=4;S_MIN,S_DELTA:need_bits=32;S_VALUE_BITS:need_bits=4;
   S_MULTIPLICAND:need_bits=value_bits;
   S_TIME_COUNT,S_FLOOR_COUNT,S_RES_COUNT,S_MAP_COUNT,S_MODE_COUNT:need_bits=6;
   S_TIME_TYPE,S_FLOOR_TYPE,S_MAP_TYPE,S_MODE_WINDOW,S_MODE_TRANSFORM:need_bits=16;
   S_F0_ORDER,S_F0_AMPOFF,S_F0_BOOK,S_F1_MASTER,S_F1_SUBBOOK,S_RES_CLASSBOOK,S_RES_BOOK,
    S_MAP_COUPLECOUNT,S_MAP_TIME,S_MAP_FLOOR,S_MAP_RES,S_MODE_MAPPING:need_bits=8;
   S_F0_RATE,S_F0_BARK:need_bits=16;S_F0_AMPBITS:need_bits=6;S_F0_BOOKS:need_bits=4;
   S_F1_PARTS:need_bits=5;S_F1_PART_CLASS:need_bits=4;S_F1_CLASS_DIM:need_bits=3;
   S_F1_CLASS_SUB,S_F1_MULT,S_MAP_RESERVED:need_bits=2;S_F1_RANGE,S_MAP_SUBCOUNT,S_MAP_MUX:need_bits=4;
   S_F1_X:need_bits=coupling_bits;
   S_RES_TYPE:need_bits=16;S_RES_BEGIN,S_RES_END,S_RES_PART:need_bits=24;S_RES_CLASSES:need_bits=6;
   S_RES_LOW:need_bits=3;S_RES_FLAG,S_MAP_SUBFLAG,S_MAP_COUPLEFLAG,S_MODE_BLOCK,S_FRAMING:need_bits=1;
   S_RES_HIGH:need_bits=5;S_RES_BOOK:need_bits=8;
   S_MAP_MAG,S_MAP_ANGLE:need_bits=coupling_bits;
   default:need_bits=0;
  endcase
 end
 assign consume=setup_packet&&header_bytes>=7&&need_bits!=0&&bit_count>=need_bits;
 // Keep the packet stream stalled after the setup packet's last byte until
 // every buffered setup bit has been consumed and the framing bit validates.
 wire setup_target=(packet_number==2||(setup_packet&&setup_ended))&&!valid&&!error;
 assign packet_ready=!setup_target?1'b1:(setup_ended?1'b0:(header_bytes<7?1'b1:(!consume&&bit_count<=56)));
 wire take=packet_valid&&packet_ready;
 wire [31:0] field=reservoir[31:0];
 wire [23:0] order_number_mask=need_bits==24?24'hffffff:((24'd1<<need_bits)-1'b1);
 wire [23:0] order_number=field[23:0]&order_number_mask;

 task begin_save;input [5:0] length;input from_ordered;begin
  if(active_entries>=8192||length==0||length>32)begin error<=1;state<=S_DONE;end
  else begin
   save_length<=length;save_index<=length;save_reverse_index<=0;
   save_assigned<=code_marker[length];save_branch<=code_marker[length];save_reversed<=0;
   save_from_ordered<=from_ordered;
   if(length<32&&(code_marker[length]>>length)!=0)begin error<=1;state<=S_DONE;end
   else state<=S_SAVE_DOWN;
  end
 end endtask

 always @(posedge clk)begin
  if(reset)begin
   state<=S_COUNT;packet_number<=0;header_bytes<=0;setup_packet<=0;setup_ended<=0;
   reservoir<=0;bit_count<=0;valid<=0;error<=0;codebook_count<=0;
   active_entries<=0;multiplicand_count<=0;book_index<=0;floor_count<=0;
   residue_count<=0;mapping_count<=0;mode_count<=0;mode_blockflags<=0;mode_mappings<=0;
  end else begin
   if(take)begin
    if(packet_start)begin
     header_bytes<=0;
     if(packet_number==2&&!valid)begin setup_packet<=1;setup_ended<=0;reservoir<=0;bit_count<=0;state<=S_COUNT;end
    end
    if(setup_target)begin
     if(header_bytes<7)header_bytes<=header_bytes+1'b1;
     else begin reservoir<=reservoir|({56'd0,packet_data}<<bit_count);bit_count<=bit_count+8;end
     if(packet_end)setup_ended<=1;
    end
    if(packet_end&&packet_number<3)packet_number<=packet_number+1'b1;
   end else if(consume)begin
   reservoir<=reservoir>>need_bits;bit_count<=bit_count-need_bits;
    case(state)
     S_COUNT:begin codebook_count<=field[7:0]+1'b1;book_index<=0;active_entries<=0;multiplicand_count<=0;state<=S_SYNC;end
     S_SYNC:begin if(field[23:0]!=24'h564342)error<=1;state<=S_DIM;end
     S_DIM:begin
      dimensions<=field[15:0];book_active_start_current<=active_entries;
      book_multiplicand_start_current<=multiplicand_count;lookup_type<=0;
      minimum_value_current<=0;delta_value_current<=0;sequence_current<=0;
      if(field[15:0]==0||field[15:0]>64)error<=1;state<=S_ENTRIES;
     end
     S_ENTRIES:begin entries<=field[23:0];local_entry<=0;
      for(loop_i=1;loop_i<33;loop_i=loop_i+1)code_marker[loop_i]=0;
      if(field[23:0]==0)error<=1;state<=S_ORDERED;end
     S_ORDERED:begin ordered<=field[0];state<=field[0]?S_ORDER_LENGTH:S_SPARSE;end
     S_SPARSE:begin sparse<=field[0];state<=field[0]?S_PRESENT:S_LENGTH;end
     S_PRESENT:begin
      present<=field[0];
      if(field[0])state<=S_LENGTH;
      else if(local_entry+1'b1==entries)begin local_entry<=local_entry+1'b1;state<=S_LOOKUP;end
      else local_entry<=local_entry+1'b1;
     end
     S_LENGTH:begin
      begin_save(field[4:0]+1'b1,1'b0);
     end
     S_ORDER_LENGTH:begin current_length<=field[4:0]+1'b1;state<=S_ORDER_NUMBER;end
     S_ORDER_NUMBER:begin
      run_remaining<=order_number;
      if(local_entry+order_number>entries)begin error<=1;state<=S_DONE;end
      else if(order_number==0)begin
       if(current_length==32)begin error<=1;state<=S_DONE;end
       else begin current_length<=current_length+1'b1;state<=S_ORDER_NUMBER;end
      end else state<=S_ORDER_WRITE;
     end
     S_LOOKUP:begin
      lookup_type<=field[3:0];
      if(field[3:0]==0)state<=S_NEXT_BOOK;
      else if(field[3:0]>2)begin error<=1;state<=S_DONE;end
      else state<=S_MIN;
     end
     S_MIN:begin minimum_value_current<=field;state<=S_DELTA;end
     S_DELTA:begin delta_value_current<=field;state<=S_VALUE_BITS;end
     S_VALUE_BITS:begin value_bits<=field[3:0]+1'b1;state<=S_SEQUENCE;end
     S_SEQUENCE:begin
      sequence_current<=field[0];
      if(lookup_type==1)state<=S_CALC_INIT;
      else begin
       values_remaining<=entries*dimensions;
       if(entries*dimensions>8192-multiplicand_count)begin error<=1;state<=S_DONE;end
       else state<=S_MULTIPLICAND;
      end
     end
     S_MULTIPLICAND:begin
      multiplicand_count<=multiplicand_count+1'b1;
      values_remaining<=values_remaining-1'b1;
      if(values_remaining==1)state<=S_NEXT_BOOK;
     end
     S_TIME_COUNT:begin time_count<=field[5:0]+1'b1;item_index<=0;state<=S_TIME_TYPE;end
     S_TIME_TYPE:begin
      if(field[15:0]!=0)error<=1;
      if(item_index+1'b1==time_count)state<=S_FLOOR_COUNT;else item_index<=item_index+1'b1;
     end
     S_FLOOR_COUNT:begin floor_count<=field[5:0]+1'b1;item_index<=0;
      if(field[5:0]>=8)begin error<=1;state<=S_DONE;end else state<=S_FLOOR_TYPE;end
     S_FLOOR_TYPE:begin
      if(field[15:0]==0)state<=S_F0_ORDER;
      else if(field[15:0]==1)state<=S_F1_PARTS;
      else begin error<=1;state<=S_DONE;end
     end
     S_F0_ORDER:state<=S_F0_RATE;
     S_F0_RATE:state<=S_F0_BARK;
     S_F0_BARK:state<=S_F0_AMPBITS;
     S_F0_AMPBITS:begin if(field[5:0]==0)error<=1;state<=S_F0_AMPOFF;end
     S_F0_AMPOFF:state<=S_F0_BOOKS;
     S_F0_BOOKS:begin subbook_remaining<=field[3:0]+1'b1;state<=S_F0_BOOK;end
     S_F0_BOOK:begin
      if(field[7:0]>=codebook_count)error<=1;
      subbook_remaining<=subbook_remaining-1'b1;if(subbook_remaining==1)state<=S_NEXT_FLOOR;
     end
     S_F1_PARTS:begin
      floor1_partitions<=field[4:0];part_index<=0;floor1_max_class<=0;
      if(field[4:0]==0)state<=S_F1_MULT;else state<=S_F1_PART_CLASS;
     end
     S_F1_PART_CLASS:begin
      floor1_partition_class[part_index]<=field[3:0];if(field[3:0]>floor1_max_class)floor1_max_class<=field[3:0];
      part_index<=part_index+1'b1;
      if(part_index+1'b1==floor1_partitions)begin class_index<=0;state<=S_F1_CLASS_DIM;end
     end
     S_F1_CLASS_DIM:begin
      floor1_class_dimensions[class_index]<=field[2:0]+1'b1;
      state<=S_F1_CLASS_SUB;
     end
     S_F1_CLASS_SUB:begin
      floor1_class_subclasses[class_index]<=field[1:0];
      floor1_subbook_index<=0;
      if(field[1:0]!=0)state<=S_F1_MASTER;
      else begin subbook_remaining<=1;state<=S_F1_SUBBOOK;end
     end
     S_F1_MASTER:begin
      if(field[7:0]>=codebook_count)error<=1;
      subbook_remaining<=1<<floor1_class_subclasses[class_index];state<=S_F1_SUBBOOK;
     end
     S_F1_SUBBOOK:begin
      if(field[7:0]!=0&&field[7:0]-1'b1>=codebook_count)error<=1;
      floor1_subbook_index<=floor1_subbook_index+1'b1;
      subbook_remaining<=subbook_remaining-1'b1;
      if(subbook_remaining==1)begin
       if(class_index==floor1_max_class)state<=S_F1_MULT;
       else begin class_index<=class_index+1'b1;state<=S_F1_CLASS_DIM;end
      end
     end
     S_F1_MULT:state<=S_F1_RANGE;
     S_F1_RANGE:begin
      coupling_bits<=field[3:0];floor1_x_total<=0;part_index<=0;
      floor1_x_write<=2;
      if(floor1_partitions==0)begin floor1_x_remaining<=0;state<=S_F1_X_INIT;end
      else state<=S_F1_TOTAL_ACCUM;
     end
     S_F1_X:begin
      floor1_x_write<=floor1_x_write+1'b1;
      floor1_x_remaining<=floor1_x_remaining-1'b1;if(floor1_x_remaining==1)state<=S_NEXT_FLOOR;
     end
     S_RES_COUNT:begin residue_count<=field[5:0]+1'b1;item_index<=0;
      if(field[5:0]>=8)begin error<=1;state<=S_DONE;end else state<=S_RES_TYPE;end
     S_RES_TYPE:begin if(field[15:0]>2)error<=1;state<=S_RES_BEGIN;end
     S_RES_BEGIN:state<=S_RES_END;
     S_RES_END:state<=S_RES_PART;
     S_RES_PART:state<=S_RES_CLASSES;
     S_RES_CLASSES:begin
      residue_classifications<=field[5:0]+1'b1;
      residue_class_index<=0;state<=S_RES_CLASSBOOK;
     end
     S_RES_CLASSBOOK:begin
      if(field[7:0]>=codebook_count)error<=1;state<=S_RES_LOW;
     end
     S_RES_LOW:begin residue_cascade[residue_class_index][2:0]<=field[2:0];state<=S_RES_FLAG;end
     S_RES_FLAG:begin
      if(field[0])state<=S_RES_HIGH;
      else begin residue_cascade[residue_class_index][7:3]<=0;
       if(residue_class_index+1'b1==residue_classifications)begin residue_class_index<=0;residue_pass<=0;state<=S_RES_CHECK;end
       else begin residue_class_index<=residue_class_index+1'b1;state<=S_RES_LOW;end
      end
     end
     S_RES_HIGH:begin
      residue_cascade[residue_class_index][7:3]<=field[4:0];
      if(residue_class_index+1'b1==residue_classifications)begin residue_class_index<=0;residue_pass<=0;state<=S_RES_CHECK;end
      else begin residue_class_index<=residue_class_index+1'b1;state<=S_RES_LOW;end
     end
     S_RES_BOOK:begin
      if(residue_cascade[residue_class_index][residue_pass]&&field[7:0]>=codebook_count)error<=1;
      if(residue_pass==7)begin
       residue_pass<=0;if(residue_class_index+1'b1==residue_classifications)state<=S_NEXT_RES;
       else begin residue_class_index<=residue_class_index+1'b1;state<=S_RES_CHECK;end
      end else begin residue_pass<=residue_pass+1'b1;state<=S_RES_CHECK;end
     end
     S_MAP_COUNT:begin mapping_count<=field[5:0]+1'b1;item_index<=0;
      if(field[5:0]>=8)begin error<=1;state<=S_DONE;end else state<=S_MAP_TYPE;end
     S_MAP_TYPE:begin if(field[15:0]!=0)error<=1;state<=S_MAP_SUBFLAG;end
     S_MAP_SUBFLAG:begin
      if(field[0])state<=S_MAP_SUBCOUNT;
      else begin map_submaps<=1;state<=S_MAP_COUPLEFLAG;end
     end
     S_MAP_SUBCOUNT:begin map_submaps<=field[3:0]+1'b1;state<=S_MAP_COUPLEFLAG;end
     S_MAP_COUPLEFLAG:begin
      coupling_bits<=ilog8(channels-1'b1);
      if(field[0])state<=S_MAP_COUPLECOUNT;
      else state<=S_MAP_RESERVED;
     end
     S_MAP_COUPLECOUNT:begin
      coupling_remaining<=field[7:0]+1'b1;coupling_index<=0;
      state<=S_MAP_MAG;
     end
     // The supported profile is mono/stereo, so a coupling channel index is
     // at most one bit. Do not compare unconsumed reservoir bits above it.
     S_MAP_MAG:begin
      map_index<=field[0];
      if(field[0]>=channels)error<=1;state<=S_MAP_ANGLE;
     end
     S_MAP_ANGLE:begin
      coupling_index<=coupling_index+1'b1;
      if(field[0]>=channels||field[0]==map_index)error<=1;coupling_remaining<=coupling_remaining-1'b1;
      if(coupling_remaining==1)state<=S_MAP_RESERVED;else state<=S_MAP_MAG;
     end
     S_MAP_RESERVED:begin
      if(field[1:0]!=0)error<=1;channel_index<=0;
      if(map_submaps>1)state<=S_MAP_MUX;
      else begin mapping_mux_mem[item_index*2]<=0;mapping_mux_mem[item_index*2+1]<=0;map_index<=0;state<=S_MAP_TIME;end
     end
     S_MAP_MUX:begin
      if(field[3:0]>=map_submaps)error<=1;channel_index<=channel_index+1'b1;
      mapping_mux_mem[item_index*2+channel_index]<=field[3:0];
      if(channel_index+1'b1==channels)begin map_index<=0;state<=S_MAP_TIME;end
     end
     S_MAP_TIME:state<=S_MAP_FLOOR;
     S_MAP_FLOOR:begin
      if(field[7:0]>=floor_count)error<=1;state<=S_MAP_RES;
     end
     S_MAP_RES:begin
      if(field[7:0]>=residue_count)error<=1;map_index<=map_index+1'b1;
      if(map_index+1'b1==map_submaps)state<=S_NEXT_MAP;else state<=S_MAP_TIME;
     end
     S_MODE_COUNT:begin mode_count<=field[5:0]+1'b1;mode_index<=0;state<=S_MODE_BLOCK;end
     S_MODE_BLOCK:begin mode_blockflags[mode_index]<=field[0];state<=S_MODE_WINDOW;end
     S_MODE_WINDOW:begin if(field[15:0]!=0)error<=1;state<=S_MODE_TRANSFORM;end
     S_MODE_TRANSFORM:begin if(field[15:0]!=0)error<=1;state<=S_MODE_MAPPING;end
     S_MODE_MAPPING:begin
      if(field[7:0]>=mapping_count)error<=1;mode_index<=mode_index+1'b1;
      mode_mappings[mode_index*8 +: 8]<=field[7:0];
      if(mode_index+1'b1==mode_count)state<=S_FRAMING;else state<=S_MODE_BLOCK;
     end
     S_FRAMING:begin if(!field[0])error<=1;valid<=!error&&field[0];state<=S_DONE;end
    endcase
   end else case(state)
    S_ORDER_WRITE:begin
     begin_save(current_length,1'b1);
    end
    S_F1_X_INIT:begin
     if(floor1_x_remaining==0||coupling_bits==0)state<=S_NEXT_FLOOR;else state<=S_F1_X;
    end
    S_F1_TOTAL_ACCUM:begin
     floor1_x_total<=floor1_x_total+floor1_class_dimensions[floor1_partition_class[part_index]];
     if(part_index+1'b1==floor1_partitions)begin
      floor1_x_remaining<=floor1_x_total+floor1_class_dimensions[floor1_partition_class[part_index]];
      if(floor1_x_total+floor1_class_dimensions[floor1_partition_class[part_index]]>63)
       begin error<=1;state<=S_DONE;end
      else state<=S_F1_X_INIT;
     end else part_index<=part_index+1'b1;
    end
    S_SAVE_DOWN:begin
     if(code_marker[save_index]&1)begin
      if(save_index==1)code_marker[1]<=code_marker[1]+1'b1;
      else code_marker[save_index]<=code_marker[save_index-1]<<1;
      save_index<=save_length+1'b1;state<=S_SAVE_UP;
     end else begin
      code_marker[save_index]<=code_marker[save_index]+1'b1;
      if(save_index==1)begin save_index<=save_length+1'b1;state<=S_SAVE_UP;end
      else save_index<=save_index-1'b1;
     end
    end
    S_SAVE_UP:begin
     if(save_index>32)begin save_reverse_index<=0;save_reversed<=0;state<=S_SAVE_REVERSE;end
     else if((code_marker[save_index]>>1)==save_branch)begin
      save_branch<=code_marker[save_index];code_marker[save_index]<=code_marker[save_index-1]<<1;
      save_index<=save_index+1'b1;
     end else begin save_reverse_index<=0;save_reversed<=0;state<=S_SAVE_REVERSE;end
    end
    S_SAVE_REVERSE:begin
     save_reversed<=(save_reversed<<1)|((save_assigned>>save_reverse_index)&1'b1);
     if(save_reverse_index+1'b1==save_length)state<=S_SAVE_COMMIT;
     else save_reverse_index<=save_reverse_index+1'b1;
    end
    S_SAVE_COMMIT:begin
     active_entries<=active_entries+1'b1;
     local_entry<=local_entry+1'b1;
     if(save_from_ordered)begin
      run_remaining<=run_remaining-1'b1;
      if(run_remaining==1)begin
       if(local_entry+1'b1==entries)state<=S_LOOKUP;
       else begin current_length<=current_length+1'b1;state<=S_ORDER_NUMBER;end
      end else state<=S_ORDER_WRITE;
     end else if(local_entry+1'b1==entries)state<=S_LOOKUP;
     else state<=sparse?S_PRESENT:S_LENGTH;
    end
    S_CALC_INIT:begin calc_candidate<=1;calc_power<=1;calc_exp<=0;state<=S_CALC_POWER;end
    S_CALC_POWER:begin
     if(calc_exp<dimensions)begin calc_power<=calc_power*calc_candidate;calc_exp<=calc_exp+1'b1;end
     else if(calc_power<=entries)begin calc_candidate<=calc_candidate+1'b1;calc_power<=1;calc_exp<=0;end
     else begin
      values_remaining<=calc_candidate-1'b1;
      if(calc_candidate-1'b1>8192-multiplicand_count)begin error<=1;state<=S_DONE;end
      else state<=S_MULTIPLICAND;
     end
    end
    S_NEXT_BOOK:begin
     if(book_index+1'b1==codebook_count)begin state<=S_TIME_COUNT;end
     else begin book_index<=book_index+1'b1;state<=S_SYNC;end
    end
    S_NEXT_FLOOR:begin
     if(item_index+1'b1==floor_count)begin item_index<=0;state<=S_RES_COUNT;end
     else begin item_index<=item_index+1'b1;state<=S_FLOOR_TYPE;end
    end
    S_NEXT_RES:begin
     if(item_index+1'b1==residue_count)begin item_index<=0;state<=S_MAP_COUNT;end
     else begin item_index<=item_index+1'b1;state<=S_RES_TYPE;end
    end
    S_NEXT_MAP:begin
     if(item_index+1'b1==mapping_count)state<=S_MODE_COUNT;
     else begin item_index<=item_index+1'b1;state<=S_MAP_TYPE;end
    end
    S_RES_CHECK:begin
     if(residue_cascade[residue_class_index][residue_pass])state<=S_RES_BOOK;
     else if(residue_pass==7)begin
      residue_pass<=0;if(residue_class_index+1'b1==residue_classifications)state<=S_NEXT_RES;
      else residue_class_index<=residue_class_index+1'b1;
     end else begin
      residue_pass<=residue_pass+1'b1;
     end
    end
    S_DONE:if(setup_ended&&!valid)error<=1;
   endcase
   if(setup_ended&&bit_count<need_bits&&need_bits!=0)error<=1;
  end
 end
endmodule
