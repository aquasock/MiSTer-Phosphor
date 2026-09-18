// One-time bridge from setup-parser codeword RAM to the direct prefix cache.
module vorbis_prefix_builder(
 input wire clk,input wire reset,input wire setup_valid,input wire [13:0] active_entries,
 output reg [13:0] active_query_address=0,input wire [31:0] active_query_entry,
 input wire [31:0] active_query_codeword,input wire prefix_ready,
 output reg leaf_valid=0,input wire leaf_ready,output reg [5:0] leaf_book=0,
 output reg [31:0] leaf_codeword=0,output reg [5:0] leaf_length=0,
 output reg [17:0] leaf_symbol=0,output reg done=0,output reg error=0
);
 localparam WAIT_SETUP=0,WAIT_CACHE=1,READ_WAIT=2,LOAD=3,FINISH=4;
 reg [2:0] state=WAIT_SETUP;
 always @(posedge clk)begin
  if(reset)begin state<=WAIT_SETUP;active_query_address<=0;leaf_valid<=0;done<=0;error<=0;end
  else begin
   leaf_valid<=0;
   case(state)
    WAIT_SETUP:if(setup_valid)begin active_query_address<=0;state<=WAIT_CACHE;end
    WAIT_CACHE:if(prefix_ready)begin
     if(active_entries==0)state<=FINISH;else state<=READ_WAIT;
    end
    READ_WAIT:state<=LOAD;
    LOAD:if(leaf_ready&&!leaf_valid)begin
     if(active_query_entry[31:24]>=64)begin error<=1;state<=FINISH;end
     else begin
      leaf_book<=active_query_entry[29:24];leaf_symbol<=active_query_entry[23:6];
      leaf_length<=active_query_entry[5:0];leaf_codeword<=active_query_codeword;leaf_valid<=1;
      if(active_query_address+1'b1==active_entries)state<=FINISH;
      else begin active_query_address<=active_query_address+1'b1;state<=READ_WAIT;end
     end
    end
    FINISH:if(leaf_ready&&!leaf_valid)done<=!error;
   endcase
  end
 end
endmodule
