// Optional single-file CD navigation. Metadata is observed on accepted reader
// bytes; it never stalls playback. The table limits are implementation budgets.
module flac_album_control(
 input wire clk,reset,new_file,enabled,osd_open,
 input wire [10:0] key,
 input wire byte_valid,input wire [7:0] byte_data,
 input wire [35:0] position,
 input wire [63:0] file_size,
 input wire reader_start,landed,seek_request,
 input wire [34:0] seek_target_q,
 output reg restart=0,busy=0,resume_frame=0,
 output reg [40:0] start_offset=0,
 output reg [35:0] start_sample=0,target_sample=0,
 output reg [35:0] total_samples=0,
 output reg [15:0] min_block=0,max_block=0,
 output reg [7:0] tag=0,
 output wire available,seek_available,
 output reg current_track_valid=0,track_changed=0,
 output reg [6:0] current_track_number=0,
 output reg [35:0] current_track_start=0,current_track_end=0
);
 localparam MAGIC=0,HEADER=1,BODY=2,DONE=3;
 reg [1:0] parse_state=MAGIC;
 reg [23:0] header=0;
 reg [1:0] header_byte=0;
 reg [6:0] block_type=0;
 reg block_last=0;
 reg [23:0] remaining=0,block_position=0;
 reg [40:0] file_position=0,first_audio=0;
 reg [55:0] field=0;
 reg [63:0] seek_sample=0,seek_offset=0,track_offset=0,index_offset=0;
 wire [63:0] field_next={field[55:0],byte_data};
 reg [4:0] seek_byte=0;
 reg [9:0] seek_count=0;
 (* ramstyle="M10K" *) reg [76:0] seeks[0:511];
 reg [6:0] track_count=0;
 (* ramstyle="M10K" *) reg [35:0] tracks[0:127];
 reg [1:0] cue_phase=0;
 reg [8:0] cue_byte=0;
 reg [7:0] tracks_left=0,indexes_left=0,track_number=0;
 reg audio_track=0,cd_cue=0,cue_bad=0,cue_seen=0;
 reg [35:0] last_track=0;
 wire [64:0] cue_sample={1'b0,track_offset}+{1'b0,index_offset};
 assign seek_available=parse_state==DONE&&total_samples!=0&&min_block>=16&&max_block>=min_block;
 assign available=parse_state==DONE&&cd_cue&&!cue_bad&&track_count!=0&&total_samples!=0;
 always @(posedge clk)begin
  if(reset||new_file)begin
   parse_state<=MAGIC;header<=0;header_byte<=0;block_type<=0;block_last<=0;
   remaining<=0;block_position<=0;file_position<=0;first_audio<=0;field<=0;
   seek_sample<=0;seek_offset<=0;seek_byte<=0;seek_count<=0;
   track_count<=0;cue_phase<=0;cue_byte<=0;tracks_left<=0;indexes_left<=0;
   track_offset<=0;index_offset<=0;track_number<=0;audio_track<=0;
   cd_cue<=0;cue_bad<=0;cue_seen<=0;last_track<=0;
   total_samples<=0;min_block<=0;max_block<=0;
  end else if(byte_valid&&enabled&&parse_state!=DONE)begin
   file_position<=file_position+1'b1;
   case(parse_state)
    MAGIC:begin
     header<={header[15:0],byte_data};header_byte<=header_byte+1'b1;
     if(header_byte==3)begin
      if({header[23:0],byte_data}==32'h664c6143)parse_state<=HEADER;
      else begin parse_state<=DONE;cue_bad<=1;end
     end
    end
    HEADER:begin
     header<={header[15:0],byte_data};header_byte<=header_byte+1'b1;
     if(header_byte==3)begin
      block_type<=header[22:16];block_last<=header[23];
      remaining<={header[15:0],byte_data};block_position<=0;field<=0;seek_byte<=0;
      cue_phase<=0;cue_byte<=0;
      if(header[22:16]==5)begin
       if(cue_seen)cue_bad<=1;
       cue_seen<=1;
       if({header[15:0],byte_data}<396)cue_bad<=1;
      end
      if({header[15:0],byte_data}==0)begin
       if(header[23])begin parse_state<=DONE;first_audio<=file_position+1'b1;end
      end else parse_state<=BODY;
     end
    end
    BODY:begin
     field<=field_next[55:0];block_position<=block_position+1'b1;remaining<=remaining-1'b1;
     if(block_type==0)begin
      if(block_position==1)min_block<=field_next[15:0];
      if(block_position==3)max_block<=field_next[15:0];
      if(block_position==17)begin
       total_samples<=field_next[35:0];
       if(field_next[63:44]!=44100||field_next[43:41]!=1||field_next[40:36]!=15)cue_bad<=1;
      end
     end
     if(block_type==3)begin
      seek_byte<=seek_byte+1'b1;
      if(seek_byte==7)seek_sample<=field_next;
      if(seek_byte==15)seek_offset<=field_next;
      if(seek_byte==17)begin
       seek_byte<=0;
       if(seek_count<512&&seek_sample[63:36]==0&&seek_offset[63:41]==0&&field_next[15:0]!=0)begin
        seeks[seek_count[8:0]]<={seek_sample[35:0],seek_offset[40:0]};seek_count<=seek_count+1'b1;
       end
      end
     end
     if(block_type==5)begin
      cue_byte<=cue_byte+1'b1;
      case(cue_phase)
       0:begin
        if(cue_byte==136)cd_cue<=byte_data[7];
        if(cue_byte==395)begin
         tracks_left<=byte_data;cue_phase<=1;cue_byte<=0;
         if(byte_data==0||byte_data>100)cue_bad<=1;
        end
       end
       1:begin
        if(cue_byte==7)track_offset<=field_next;
        if(cue_byte==8)track_number<=byte_data;
        if(cue_byte==21)audio_track<=!byte_data[7];
        if(cue_byte==35)begin
         indexes_left<=byte_data;cue_byte<=0;
         if(tracks_left==0)cue_bad<=1;
         else tracks_left<=tracks_left-1'b1;
         if(byte_data!=0)cue_phase<=2;
         else if(track_number!=170)cue_bad<=1;
        end
       end
       2:begin
        if(cue_byte==7)index_offset<=field_next;
        if(cue_byte==8&&byte_data==1&&audio_track&&track_number>=1&&track_number<=99)begin
         if(cue_sample[64:36]!=0||track_count==99||(track_count!=0&&cue_sample[35:0]<=last_track))cue_bad<=1;
         else begin tracks[track_count]<=cue_sample[35:0];last_track<=cue_sample[35:0];track_count<=track_count+1'b1;end
        end
        if(cue_byte==11)begin
         cue_byte<=0;indexes_left<=indexes_left-1'b1;
         if(indexes_left==1)cue_phase<=1;
        end
       end
       default:cue_bad<=1;
      endcase
      if(remaining==1&&!(cue_phase==1&&cue_byte==35&&track_number==170&&byte_data==0&&tracks_left==1))cue_bad<=1;
     end
     if(remaining==1)begin
      header_byte<=0;
      if(block_last)begin parse_state<=DONE;first_audio<=file_position+1'b1;end
      else parse_state<=HEADER;
     end
    end
    default:parse_state<=DONE;
   endcase
  end
 end
 // Synchronous table reads; scan takes only a few dozen microseconds.
 reg [6:0] track_address=0;
 reg [8:0] seek_address=0;
 reg [35:0] track_q=0;
 reg [76:0] seek_q=0;
 localparam IDLE=0,TRACK_WAIT=1,TRACK_READ=2,CHOOSE=3,SEEK_WAIT=4,SEEK_READ=5,ISSUE=6,WAIT_START=7,WAIT_LAND=8,CONVERT=9,CONVERT_START=10;
 reg [3:0] nav_state=IDLE;
 // Idle observer shares the existing cue RAM port; navigation always wins.
 reg [6:0] monitor_address=0;
 reg [1:0] monitor_state=0;
 reg [35:0] monitor_position=0,monitor_start=0;
 wire [6:0] read_track_address=nav_state==IDLE?monitor_address:track_address;
 always @(posedge clk)begin track_q<=tracks[read_track_address];seek_q<=seeks[seek_address];end
 task publish_track(input [6:0] number,input [35:0] start_value,end_value);
 begin
  current_track_valid<=end_value>start_value;
  current_track_number<=number;current_track_start<=start_value;current_track_end<=end_value;
  track_changed<=end_value>start_value&&(!current_track_valid||number!=current_track_number);
  monitor_state<=0;
 end
 endtask
 always @(posedge clk)begin
  track_changed<=0;
  if(reset||new_file)begin
   current_track_valid<=0;current_track_number<=0;current_track_start<=0;current_track_end<=0;
   monitor_state<=0;monitor_address<=0;monitor_position<=0;monitor_start<=0;
  end else if(!enabled||!seek_available||nav_state!=IDLE||seek_request)begin
   monitor_state<=0;current_track_valid<=0;
  end else if(!available)begin
   publish_track(7'd1,36'd0,total_samples);
  end else case(monitor_state)
   0:begin monitor_position<=position;monitor_address<=0;monitor_start<=0;monitor_state<=1;end
   1:monitor_state<=2;
   2:begin
    if(track_q>monitor_position)begin
     if(monitor_address==0)publish_track(7'd1,36'd0,track_q);
     else publish_track(monitor_address,monitor_start,track_q<total_samples?track_q:total_samples);
    end else if(monitor_address+1'b1==track_count)begin
     publish_track(track_count,track_q,total_samples);
    end else begin monitor_start<=track_q;monitor_address<=monitor_address+1'b1;monitor_state<=1;end
   end
   default:monitor_state<=0;
  endcase
 end
 reg convert_start=0;
 wire convert_done,convert_busy;
 reg [34:0] requested_time=0;
 wire [47:0] converted_sample;
 media_ui_divider seek_time(.clk(clk),.ce(1'b1),.start(convert_start),
  .numerator({13'd0,requested_time}*48'd49),.denominator(35'd400),
  .busy(convert_busy),.done(convert_done),.quotient(converted_sample),.remainder());
 reg key_toggle=0,n_down=0,p_down=0,forward=0;
 reg [35:0] request_position=0,last_start=0,previous_start=0;
 reg [35:0] best_sample=0;
 reg [40:0] best_offset=0;
 wire [41:0] absolute_offset={1'b0,first_audio}+{1'b0,seek_q[40:0]};
 always @(posedge clk)begin
  restart<=0;convert_start<=0;key_toggle<=key[10];
  if(key_toggle!=key[10])begin
   if(key[8:0]==9'h031)n_down<=key[9];
   if(key[8:0]==9'h04d)p_down<=key[9];
  end
  if(reset||new_file)begin
   busy<=0;resume_frame<=0;start_offset<=0;start_sample<=0;target_sample<=0;tag<=reset?8'd0:tag+1'b1;nav_state<=IDLE;
   track_address<=0;seek_address<=0;forward<=0;request_position<=0;last_start<=0;previous_start<=0;best_sample<=0;best_offset<=0;
   if(reset)begin n_down<=0;p_down<=0;end
  end else case(nav_state)
   IDLE:if(seek_request&&enabled&&seek_available)begin
    busy<=1;requested_time<=seek_target_q;nav_state<=CONVERT_START;
   end else if(key_toggle!=key[10]&&key[9]&&available&&enabled&&!osd_open&&
       ((key[8:0]==9'h031&&!n_down)||(key[8:0]==9'h04d&&!p_down)))begin
    forward<=key[8:0]==9'h031;request_position<=position;track_address<=0;
    last_start<=0;previous_start<=0;busy<=1;nav_state<=TRACK_WAIT;
   end
   CONVERT_START:if(!convert_busy)begin convert_start<=1;nav_state<=CONVERT;end
   CONVERT:if(convert_done)begin
    target_sample<=converted_sample>={12'd0,total_samples}?total_samples-1'b1:converted_sample[35:0];
    nav_state<=CHOOSE;
   end
   TRACK_WAIT:nav_state<=TRACK_READ;
   TRACK_READ:begin
    if(track_q>request_position)begin
     target_sample<=(forward||track_address==0)?track_q:previous_start;nav_state<=CHOOSE;
    end else if(track_address+1'b1==track_count)begin
     if(forward)begin busy<=0;nav_state<=IDLE;end
     else begin target_sample<=track_address==0?track_q:last_start;nav_state<=CHOOSE;end
    end else begin
     previous_start<=track_address==0?track_q:last_start;last_start<=track_q;track_address<=track_address+1'b1;nav_state<=TRACK_WAIT;
    end
   end
   CHOOSE:begin
    best_sample<=0;best_offset<=first_audio;seek_address<=0;
    if(target_sample>=total_samples)begin busy<=0;nav_state<=IDLE;end
    else nav_state<=seek_count==0?ISSUE:SEEK_WAIT;
   end
   SEEK_WAIT:nav_state<=SEEK_READ;
   SEEK_READ:begin
    if(seek_q[76:41]<=target_sample&&seek_q[76:41]>=best_sample&&!absolute_offset[41]&&{22'd0,absolute_offset}<file_size)begin
     best_sample<=seek_q[76:41];best_offset<=absolute_offset[40:0];
    end
    if({1'b0,seek_address}+10'd1==seek_count)nav_state<=ISSUE;
    else begin seek_address<=seek_address+1'b1;nav_state<=SEEK_WAIT;end
   end
   ISSUE:begin
    start_offset<=best_offset;start_sample<=best_sample;resume_frame<=1;tag<=tag+1'b1;restart<=1;nav_state<=WAIT_START;
   end
   WAIT_START:if(reader_start)nav_state<=WAIT_LAND;
   WAIT_LAND:if(landed)begin busy<=0;nav_state<=IDLE;end
   default:begin busy<=0;nav_state<=IDLE;end
  endcase
 end
endmodule
