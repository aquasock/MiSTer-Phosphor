// Eight-bit direct Huffman prefix table for up to 64 Vorbis codebooks.
// Short leaves are replicated across all unused suffix combinations, allowing
// a packet reservoir to peek eight bits and consume only the matched length.
module vorbis_huffman_prefix(
 input wire clk,input wire reset,
 input wire leaf_valid,output wire leaf_ready,input wire [5:0] leaf_book,
 input wire [31:0] leaf_codeword,input wire [5:0] leaf_length,input wire [17:0] leaf_symbol,
 input wire lookup_valid,input wire [5:0] lookup_book,input wire [7:0] lookup_bits,
 output reg lookup_result_valid=0,output reg lookup_hit=0,
 output reg [5:0] lookup_length=0,output reg [17:0] lookup_symbol=0,
 output reg ready=0,output reg error=0
);
 localparam CLEAR=0,IDLE=1,FILL=2;
 reg [1:0] state=CLEAR;
 reg [13:0] clear_address=0;
 reg [5:0] fill_book=0,fill_length=0;
 reg [7:0] fill_code=0,fill_suffix=0,fill_last=0;
 reg [17:0] fill_symbol=0;
 reg lookup_pending=0;
 wire [13:0] lookup_address={lookup_book,lookup_bits};
 wire [13:0] fill_address={fill_book,(fill_code|(fill_suffix<<fill_length))};
 wire prefix_write=state==CLEAR||state==FILL;
 wire [13:0] prefix_write_address=state==CLEAR?clear_address:fill_address;
 wire [24:0] prefix_write_data=state==CLEAR?25'd0:{1'b1,fill_length,fill_symbol};
 wire [24:0] prefix_read_data;
 vorbis_setup_ram #(.WIDTH(25),.DEPTH(16384),.ADDR_WIDTH(14)) prefix_mem(clk,
  prefix_write,prefix_write_address,prefix_write_data,lookup_address,prefix_read_data);
 assign leaf_ready=state==IDLE;

 always @(posedge clk)begin
  if(reset)begin state<=CLEAR;clear_address<=0;ready<=0;error<=0;lookup_result_valid<=0;lookup_pending<=0;end
  else begin
   lookup_result_valid<=lookup_pending;lookup_pending<=lookup_valid&&ready&&state!=CLEAR;
   if(lookup_pending)begin
    lookup_hit<=prefix_read_data[24];lookup_length<=prefix_read_data[23:18];lookup_symbol<=prefix_read_data[17:0];
   end
   case(state)
    CLEAR:begin
     if(clear_address==16383)begin clear_address<=0;ready<=1;state<=IDLE;end
     else clear_address<=clear_address+1'b1;
    end
    IDLE:if(leaf_valid)begin
     if(leaf_book>=64||leaf_length==0||leaf_length>32)error<=1;
     else if(leaf_length<=8)begin
      fill_book<=leaf_book;fill_length<=leaf_length;fill_code<=leaf_codeword[7:0];
      fill_symbol<=leaf_symbol;fill_suffix<=0;fill_last<=(9'd1<<(8-leaf_length))-1'b1;state<=FILL;
     end
    end
    FILL:begin
     if(fill_suffix==fill_last)state<=IDLE;else fill_suffix<=fill_suffix+1'b1;
    end
   endcase
  end
 end
endmodule
