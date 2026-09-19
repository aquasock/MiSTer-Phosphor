// Streaming reader for the deliberately narrow album-container profile:
// POSIX ustar, regular files, no compression, no PAX/GNU extensions.
// Payload bytes are skipped logically while the mounted-file reader keeps
// advancing. Each entry is published after its 512-byte header is complete.
module media_tar_index(
 input  wire        clk,
 input  wire        reset,
 input  wire        enable,
 input  wire        jump,
 input  wire [40:0] jump_position,
 input  wire        byte_valid,
 input  wire [7:0]  byte_data,
 input  wire        byte_eof,
 output reg         entry_valid=0,
 output reg  [8:0]  entry_number=0,
 output reg  [2:0]  entry_kind=0,
 output reg  [40:0] entry_offset=0,
 output reg  [40:0] entry_size=0,
 output reg  [31:0] entry_basename_hash=0,
 output reg  [31:0] entry_name_hash=0,
 output reg  [6:0]  entry_name_length=0,
 output reg         ready=0,
 output reg         done=0,
 output reg         error=0
);
 localparam KIND_OTHER=3'd0,KIND_FLAC=3'd1,KIND_CUE=3'd2,
            KIND_MP3=3'd3,KIND_WAV=3'd4,KIND_OGG=3'd5,KIND_INDEX=3'd6,KIND_M3U=3'd7;
 localparam [31:0] FNV_OFFSET=32'h811c9dc5;

 reg[8:0] header_pos=0;
 reg[40:0] absolute_pos=0,payload_left=0,size_accum=0;
 reg header_zero=1,magic_ok=1,regular_file=1;
 reg[7:0] last0=0,last1=0,last2=0,last3=0,last4=0;
 reg[31:0] name_hash=FNV_OFFSET,hash_d1=FNV_OFFSET,hash_d2=FNV_OFFSET,
           hash_d3=FNV_OFFSET,hash_d4=FNV_OFFSET,hash_d5=FNV_OFFSET;
 reg[6:0] name_length=0;
 wire[7:0] slash=byte_data==8'h5c ? 8'h2f : byte_data;
 wire[7:0] lower=(slash>=8'h41&&slash<=8'h5a)?slash+8'h20:slash;
 wire ext_flac={last4,last3,last2,last1,last0}==40'h2e666c6163;
 wire ext_cue ={last3,last2,last1,last0}==32'h2e637565;
 wire ext_art ={last3,last2,last1,last0}==32'h2e617274;
 wire ext_mp3 ={last3,last2,last1,last0}==32'h2e6d7033;
 wire ext_wav ={last3,last2,last1,last0}==32'h2e776176;
 wire ext_ogg ={last3,last2,last1,last0}==32'h2e6f6767;
 wire ext_index={last3,last2,last1,last0}==32'h2e696478;
 wire ext_m3u={last3,last2,last1,last0}==32'h2e6d3375;
 wire[2:0] detected_kind=ext_flac?KIND_FLAC:(ext_cue||ext_art)?KIND_CUE:
                          ext_mp3?KIND_MP3:ext_wav?KIND_WAV:
                          ext_ogg?KIND_OGG:ext_index?KIND_INDEX:ext_m3u?KIND_M3U:KIND_OTHER;
 wire[31:0] detected_hash=ext_flac?hash_d5:
                           (ext_cue||ext_art||ext_mp3||ext_wav||ext_ogg||ext_index||ext_m3u)?hash_d4:name_hash;
 wire[40:0] padded_size=(size_accum+41'd511)&~41'd511;

 always @(posedge clk)begin
  entry_valid<=0;
  if(reset||!enable)begin
   header_pos<=0;absolute_pos<=0;payload_left<=0;size_accum<=0;
   header_zero<=1;magic_ok<=1;regular_file<=1;entry_number<=0;
   last0<=0;last1<=0;last2<=0;last3<=0;last4<=0;name_length<=0;
   name_hash<=FNV_OFFSET;hash_d1<=FNV_OFFSET;hash_d2<=FNV_OFFSET;
   hash_d3<=FNV_OFFSET;hash_d4<=FNV_OFFSET;hash_d5<=FNV_OFFSET;
   ready<=0;done<=0;error<=0;
  end else if(jump)begin
   // A seek-based TAR walker may skip an entry's padded payload.  Retain the
   // entries already published, but restart header parsing at the explicitly
   // supplied absolute TAR byte position.
   header_pos<=0;absolute_pos<=jump_position;payload_left<=0;size_accum<=0;
   header_zero<=1;magic_ok<=1;regular_file<=1;
   last0<=0;last1<=0;last2<=0;last3<=0;last4<=0;name_length<=0;
   name_hash<=FNV_OFFSET;hash_d1<=FNV_OFFSET;hash_d2<=FNV_OFFSET;
   hash_d3<=FNV_OFFSET;hash_d4<=FNV_OFFSET;hash_d5<=FNV_OFFSET;
  end else if(byte_valid&&!done)begin
   if(byte_eof)begin
    done<=1;
    if(header_pos!=0||payload_left!=0)error<=1;
   end else begin
    absolute_pos<=absolute_pos+1'b1;
    if(payload_left!=0)payload_left<=payload_left-1'b1;
    else begin
     if(byte_data!=0)header_zero<=0;
     if(header_pos<100&&byte_data!=0)begin
      if(name_length<7'd100)name_length<=name_length+1'b1;
      last4<=last3;last3<=last2;last2<=last1;last1<=last0;last0<=lower;
      hash_d5<=hash_d4;hash_d4<=hash_d3;hash_d3<=hash_d2;
      hash_d2<=hash_d1;hash_d1<=name_hash;
      // FNV prime 0x01000193 expressed as shifts/adds so this bookkeeping
      // can never consume the core's final available DSP block.
      name_hash<=((name_hash^lower)<<24)+((name_hash^lower)<<8)+
                 ((name_hash^lower)<<7)+((name_hash^lower)<<4)+
                 ((name_hash^lower)<<1)+(name_hash^lower);
     end
     if(header_pos>=124&&header_pos<=135&&byte_data>=8'h30&&byte_data<=8'h37)
      size_accum<=(size_accum<<3)+{38'd0,byte_data[2:0]};
     if(header_pos==156)regular_file<=byte_data==0||byte_data==8'h30;
     if(header_pos>=257&&header_pos<=261)begin
      case(header_pos)
       257:if(byte_data!=8'h75)magic_ok<=0;
       258:if(byte_data!=8'h73)magic_ok<=0;
       259:if(byte_data!=8'h74)magic_ok<=0;
       260:if(byte_data!=8'h61)magic_ok<=0;
       261:if(byte_data!=8'h72)magic_ok<=0;
      endcase
     end
     if(header_pos==511)begin
      if(header_zero)begin done<=1;ready<=entry_number!=0;end
      else if(!magic_ok)begin done<=1;error<=1;end
      else begin
       if(regular_file)begin
        entry_valid<=1;entry_number<=entry_number+1'b1;
        entry_kind<=detected_kind;entry_offset<=absolute_pos+1'b1;
        entry_size<=size_accum;entry_basename_hash<=detected_hash;
        entry_name_hash<=name_hash;entry_name_length<=name_length;
       end
       payload_left<=padded_size;header_pos<=0;size_accum<=0;
       header_zero<=1;magic_ok<=1;regular_file<=1;
       last0<=0;last1<=0;last2<=0;last3<=0;last4<=0;name_length<=0;
       name_hash<=FNV_OFFSET;hash_d1<=FNV_OFFSET;hash_d2<=FNV_OFFSET;
       hash_d3<=FNV_OFFSET;hash_d4<=FNV_OFFSET;hash_d5<=FNV_OFFSET;
      end
     end else header_pos<=header_pos+1'b1;
    end
   end
  end
 end
endmodule
