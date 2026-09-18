// Stores one reconstructed Floor-1 point set, renders active points in
// ascending X order, converts the integer dB curve through the Vorbis lookup
// table, and applies it in-place to one interleaved residue channel.
module vorbis_floor1_apply(
 input wire clk,input wire reset,input wire load_start,
 input wire point_valid,output wire point_ready,input wire [15:0] point_x,
 input wire [8:0] point_y,input wire point_active,
 input wire apply_start,input wire floor_present,input wire channel,
 input wire [11:0] spectral_bins,input wire [2:0] multiplier,
 output reg read_valid=0,input wire read_ready,output reg [11:0] read_address=0,
 input wire read_data_valid,input wire signed [31:0] read_data,
 output reg set_valid=0,input wire set_ready,output reg [11:0] set_address=0,
 output reg signed [31:0] set_value=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,LOAD=1,INIT=2,FIND=3,FIND_DONE=4,PREP=5,READ_REQ=6,
  READ_WAIT=7,MULTIPLY=8,WRITE_REQ=9,ADVANCE=10,ZERO_WRITE=11,FINISH=12,
  SLOPE_DIV_START=13,SLOPE_DIV_WAIT=14;
 reg [3:0] state=IDLE;reg [6:0] point_count=0,scan=0;
 reg [15:0] xs[0:64];reg [8:0] ys[0:64];reg active[0:64];
 reg [11:0] lx=0,hx=0,x=0;reg signed [11:0] ly=0,hy=0,y=0;
 reg best_valid=0;reg [15:0] best_x=0;reg [8:0] best_y=0;
 integer dy,adx,ady,base,sy,err,ady_remainder;
 reg [11:0] slope_numerator=0,slope_denominator=1;reg slope_negative=0;
 wire slope_divider_ready,slope_divider_done,slope_divider_error;
 wire [11:0] slope_quotient,slope_remainder;
 reg [7:0] curve_index=0;reg [31:0] gain=0;reg signed [31:0] residue=0;
 reg signed [63:0] product;
 reg [31:0] inverse_db[0:255];
 initial $readmemh("rtl/audio/vorbis/vorbis_floor1_inverse_db.hex",inverse_db);
 vorbis_unsigned_divider #(.WIDTH(12)) slope_divider(.clk(clk),.reset(reset),
  .start(state==SLOPE_DIV_START),.numerator(slope_numerator),.denominator(slope_denominator),
  .ready(slope_divider_ready),.done(slope_divider_done),.error(slope_divider_error),
  .quotient(slope_quotient),.remainder(slope_remainder));
 assign ready=state==IDLE||state==LOAD;
 assign point_ready=state==LOAD&&point_count<65;
 function signed [31:0] sat32;input signed [63:0] value;begin
  if(value>64'sh000000007fffffff)sat32=32'sh7fffffff;
  else if(value< -64'sh0000000080000000)sat32=32'sh80000000;
  else sat32=value[31:0];
 end endfunction
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;read_valid<=0;set_valid<=0;done<=0;error<=0;point_count<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(load_start)begin point_count<=0;error<=0;state<=LOAD;end
    LOAD:begin
     if(point_valid&&point_ready)begin
      xs[point_count]<=point_x;ys[point_count]<=point_y;active[point_count]<=point_active;
      point_count<=point_count+1'b1;
     end
     if(apply_start)begin
      if(spectral_bins==0)state<=FINISH;
      else if(!floor_present)begin x<=0;state<=ZERO_WRITE;end
      else if(point_count<2)begin error<=1;state<=FINISH;end
      else state<=INIT;
     end
    end
    INIT:begin lx<=0;ly<=ys[0]*multiplier;scan<=1;best_valid<=0;state<=FIND;end
    FIND:begin
     if(scan<point_count)begin
      if(active[scan]&&xs[scan]>lx&&(!best_valid||xs[scan]<best_x))begin
       best_valid<=1;best_x<=xs[scan];best_y<=ys[scan];
      end
      scan<=scan+1'b1;
     end else state<=FIND_DONE;
    end
    FIND_DONE:begin
     if(best_valid)begin hx<=best_x[11:0];hy<=best_y*multiplier;end
     else begin hx<=spectral_bins;hy<=ly;end
     state<=PREP;
    end
    PREP:begin
     x<=lx;y<=ly;err=0;dy=hy-ly;adx=hx-lx;ady=dy<0?-dy:dy;
     if(adx<=0)begin error<=1;state<=FINISH;end
     else begin
      slope_numerator<=ady[11:0];slope_denominator<=adx[11:0];slope_negative<=dy<0;
      state<=SLOPE_DIV_START;
     end
    end
    SLOPE_DIV_START:if(slope_divider_ready)state<=SLOPE_DIV_WAIT;
    SLOPE_DIV_WAIT:if(slope_divider_done)begin
     if(slope_divider_error)begin error<=1;state<=FINISH;end
     else begin
      if(slope_negative)begin base=-$signed({1'b0,slope_quotient});sy=-$signed({1'b0,slope_quotient})-1;end
      else begin base=$signed({1'b0,slope_quotient});sy=$signed({1'b0,slope_quotient})+1;end
      ady_remainder=slope_remainder;state<=READ_REQ;
     end
    end
    READ_REQ:begin
     if(x>=spectral_bins)state<=FINISH;
     else if(read_ready)begin
      curve_index<=y<0?0:(y>255?255:y[7:0]);gain<=inverse_db[y<0?0:(y>255?255:y[7:0])];
      read_address<=x*2+channel;read_valid<=1;state<=READ_WAIT;
     end
    end
    READ_WAIT:begin read_valid<=0;if(read_data_valid)begin residue<=read_data;state<=MULTIPLY;end end
    MULTIPLY:begin product=$signed(residue)*$signed({1'b0,gain});set_value<=sat32(product>>>31);state<=WRITE_REQ;end
    WRITE_REQ:if(set_ready)begin set_address<=x*2+channel;set_valid<=1;state<=ADVANCE;end
    ADVANCE:begin
     set_valid<=0;
     if(x+1'b1>=hx||x+1'b1>=spectral_bins)begin
      lx<=hx;ly<=hy;scan<=1;best_valid<=0;
      if(x+1'b1>=spectral_bins)state<=FINISH;else state<=FIND;
     end else begin
      x<=x+1'b1;err=err+ady_remainder;
      if(err>=adx)begin err=err-adx;y<=y+sy;end else y<=y+base;
      state<=READ_REQ;
     end
    end
    ZERO_WRITE:if(set_ready)begin
     set_address<=x*2+channel;set_value<=0;set_valid<=1;state<=ADVANCE;
     hx<=spectral_bins;hy<=0;ly<=0;adx=1;ady_remainder=0;base=0;sy=0;err=0;
    end
    FINISH:begin read_valid<=0;set_valid<=0;done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
