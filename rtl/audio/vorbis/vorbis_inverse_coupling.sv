// In-place Vorbis square-polar to Cartesian residue conversion. Coupling
// steps are traversed in reverse setup order, and stereo residue values are
// addressed in their type-2 interleaved workspace layout.
module vorbis_inverse_coupling(
 input wire clk,input wire reset,input wire start,
 input wire [8:0] coupling_steps,input wire [11:0] spectral_bins,
 output reg [7:0] coupling_query=0,input wire coupling_magnitude,input wire coupling_angle,
 output reg read_valid=0,input wire read_ready,output reg [11:0] read_address=0,
 input wire read_data_valid,input wire signed [31:0] read_data,
 output reg set_valid=0,input wire set_ready,output reg [11:0] set_address=0,
 output reg signed [31:0] set_value=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,READ_M_REQ=1,READ_M_WAIT=2,READ_A_REQ=3,READ_A_WAIT=4,
  CALCULATE=5,WRITE_M=6,WRITE_A=7,NEXT_BIN=8,NEXT_STEP=9,FINISH=10,QUERY_WAIT=11;
 reg [3:0] state=IDLE;reg [11:0] bin=0;reg signed [31:0] magnitude=0,angle=0,new_m=0,new_a=0;
 assign ready=state==IDLE;
 function signed [31:0] sat32;input signed [32:0] value;begin
  if(value>33'sh07fffffff)sat32=32'sh7fffffff;
  else if(value< -33'sh080000000)sat32=32'sh80000000;
  else sat32=value[31:0];
 end endfunction
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;read_valid<=0;set_valid<=0;done<=0;error<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     error<=0;bin<=0;
     if(coupling_steps==0||spectral_bins==0)state<=FINISH;
     else begin coupling_query<=coupling_steps-1'b1;state<=QUERY_WAIT;end
    end
    QUERY_WAIT:state<=READ_M_REQ;
    READ_M_REQ:if(read_ready)begin read_address<=bin*2+coupling_magnitude;read_valid<=1;state<=READ_M_WAIT;end
    READ_M_WAIT:begin
     read_valid<=0;if(read_data_valid)begin magnitude<=read_data;state<=READ_A_REQ;end
    end
    READ_A_REQ:if(read_ready)begin read_address<=bin*2+coupling_angle;read_valid<=1;state<=READ_A_WAIT;end
    READ_A_WAIT:begin
     read_valid<=0;if(read_data_valid)begin angle<=read_data;state<=CALCULATE;end
    end
    CALCULATE:begin
     if(magnitude>0)begin
      if(angle>0)begin new_m<=magnitude;new_a<=sat32($signed({magnitude[31],magnitude})-$signed({angle[31],angle}));end
      else begin new_a<=magnitude;new_m<=sat32($signed({magnitude[31],magnitude})+$signed({angle[31],angle}));end
     end else begin
      if(angle>0)begin new_m<=magnitude;new_a<=sat32($signed({magnitude[31],magnitude})+$signed({angle[31],angle}));end
      else begin new_a<=magnitude;new_m<=sat32($signed({magnitude[31],magnitude})-$signed({angle[31],angle}));end
     end
     state<=WRITE_M;
    end
    WRITE_M:if(set_ready)begin set_address<=bin*2+coupling_magnitude;set_value<=new_m;set_valid<=1;state<=WRITE_A;end
    WRITE_A:begin
     set_valid<=0;
     if(set_ready)begin set_address<=bin*2+coupling_angle;set_value<=new_a;set_valid<=1;state<=NEXT_BIN;end
    end
    NEXT_BIN:begin
     set_valid<=0;
     if(bin+1'b1<spectral_bins)begin bin<=bin+1'b1;state<=READ_M_REQ;end
     else state<=NEXT_STEP;
    end
    NEXT_STEP:begin
     if(coupling_query==0)state<=FINISH;
     else begin coupling_query<=coupling_query-1'b1;bin<=0;state<=QUERY_WAIT;end
    end
    FINISH:begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
