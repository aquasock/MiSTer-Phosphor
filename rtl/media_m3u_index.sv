// Filename index for plain or extended M3U playlists. Every non-empty,
// non-comment line is a track reference. Paths are ASCII-case-folded and
// backslashes are normalized to slashes before hashing.
module media_m3u_index(
 input wire clk,reset,begin_file,byte_valid,input wire[7:0] byte_data,input wire byte_eof,
 output reg entry_write=0,output reg[7:0] entry_address=0,
 output reg[31:0] entry_hash=0,output reg[6:0] entry_length=0,
 output reg[7:0] entry_count=0,output reg ready=0,error=0
);
 localparam[31:0] FNV_OFFSET=32'h811c9dc5;
 reg line_start=1,comment=0,filename=0,overflow=0;
 reg[31:0] hash=FNV_OFFSET;reg[6:0] length=0;
 wire newline=byte_data==8'h0a||byte_data==8'h0d;
 wire[7:0] slash=byte_data==8'h5c ? 8'h2f : byte_data;
 wire[7:0] normalized=(slash>=8'h41&&slash<=8'h5a)?slash+8'h20:slash;
 wire[31:0] mixed=hash^normalized;
 wire[31:0] hash_next=(mixed<<24)+(mixed<<8)+(mixed<<7)+(mixed<<4)+(mixed<<1)+mixed;
 task finish_line;begin
  if(filename)begin
   if(entry_count<8'd255&&!overflow)begin
    entry_write<=1;entry_address<=entry_count;entry_hash<=hash;
    entry_length<=length;entry_count<=entry_count+1'b1;
   end else error<=1;
  end
  line_start<=1;comment<=0;filename<=0;overflow<=0;
  hash<=FNV_OFFSET;length<=0;
 end endtask
 always @(posedge clk)begin
  entry_write<=0;
  if(reset||begin_file)begin
   line_start<=1;comment<=0;filename<=0;overflow<=0;hash<=FNV_OFFSET;length<=0;
   entry_address<=0;entry_hash<=0;entry_length<=0;entry_count<=0;ready<=0;error<=0;
  end else if(byte_valid&&!ready)begin
   if(byte_eof)begin finish_line();ready<=1;end
   else if(newline)finish_line();
   else if(line_start)begin
    line_start<=0;
    if(byte_data==8'h23)comment<=1;
    else begin filename<=1;hash<=hash_next;length<=1;end
   end else if(filename)begin
    hash<=hash_next;
    if(length<7'd100)length<=length+1'b1;else overflow<=1;
   end
  end
 end
endmodule
