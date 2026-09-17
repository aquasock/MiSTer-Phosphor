// Nine-cycle post-scaler renderer, matching O-scope. Independent FFT bands
// drive hard-edged blocks: no interpolation, turbulence or color blending.
module media_fire_renderer(
 input wire clk,active,input wire [255:0] levels,
 input wire [23:0] rgb,input wire hs,vs,de,layout_de,
 output reg [23:0] rgb_out=0,output reg hs_out=0,vs_out=0,de_out=0
);
 reg [11:0] x=0,y=0,width=0,height=0;
 reg de_d=0,vs_d=0,frame_active=0;
 reg [255:0] snapshot=0;
 reg [5:0] copy=32;
 (* ramstyle="M10K, no_rw_check" *) reg [15:0] bands[0:31];
 reg [15:0] band_state=0;
 wire [4:0] band_q=band_state[4:0],peak_q=band_state[9:5];
 reg [4:0] column=0;
 reg copy_phase=0,clear_peaks=1,clear_pending=1;
 // Share the existing band RAM: level, peak and six-bit frame age.
 // Hold for half a second, then fall one block every four video frames.
 wire [4:0] incoming=snapshot[7:3];
 wire [4:0] old_peak=band_state[9:5];
 wire [5:0] old_age=band_state[15:10];
 wire renew_peak=incoming!=0&&incoming>=old_peak;
 wire [4:0] next_peak=clear_peaks?incoming:renew_peak?incoming:
                         old_age==0&&old_peak!=0?old_peak-5'd1:old_peak;
 wire [5:0] next_age=clear_peaks||renew_peak?6'd30:
                        old_age!=0?old_age-6'd1:6'd3;
 // A remainder accumulator divides the viewport into exactly 32 columns.
 reg [12:0] phase_x=0;
 wire [12:0] next_x=phase_x+13'd32;
 wire [11:0] base_y=height;
 wire [11:0] max_height=(height>>1)+(height>>2);
 // Resolution-derived geometry settles in blanking, not on pixel paths.
 reg [11:0] row_pitch=0,grid_top=0;
 always @(posedge clk)begin
  row_pitch<=max_height>>5;grid_top<=base_y-(row_pitch<<5);
 end
 wire [11:0] row_gap=row_pitch>>2;
 reg [11:0] row_edge=0;
 reg [5:0] row_needed=32;
 always @(posedge clk)begin
  de_d<=layout_de;vs_d<=vs;
  if(!active)clear_pending<=1;else if(vs&&!vs_d)clear_pending<=0;
  if(layout_de)begin
   x<=x+1'b1;
   if(next_x>={1'b0,width})begin phase_x<=next_x-{1'b0,width};column<=column+1'b1;end
   else phase_x<=next_x;
  end else begin x<=0;phase_x<=0;column<=0;end
  if(de_d&&!layout_de)begin
   width<=x;y<=y+1'b1;
   if(row_needed!=0&&y+12'd1>=row_edge)begin
    row_edge<=row_edge+row_pitch;row_needed<=row_needed-1'b1;
   end
  end
  if(vs&&!vs_d)begin
   height<=y;y<=0;snapshot<=levels;copy<=0;frame_active<=active;
   row_edge<=grid_top+row_pitch;row_needed<=32;copy_phase<=0;
   clear_peaks<=clear_pending||!frame_active||!active;
  end else if(copy<32)begin
   copy_phase<=!copy_phase;
   if(copy_phase)begin
    bands[copy[4:0]]<={next_age,next_peak,incoming};
    snapshot<=snapshot>>8;copy<=copy+1'b1;
   end
  end
  band_state<=bands[copy<32?copy[4:0]:column];
 end
 (* altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) reg [26:0] video[0:7];
 (* altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) reg [7:0] enable_pipe=0;
 // Only lit/color selection bits traverse the pipe, not repeated RGB values.
 (* altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) reg [6:0] lit_pipe=0,orange_pipe=0,peak_pipe=0;
 reg cell_visible=0,peak_visible=0;
 reg [5:0] needed_q=0;
 always @(posedge clk)begin
  video[0]<={hs,vs,de,rgb};
  for(integer k=1;k<8;k=k+1)video[k]<=video[k-1];
  enable_pipe<={enable_pipe[6:0],frame_active&&active&&layout_de&&copy==32&&width>=256&&height>=240};
  needed_q<=row_needed;
  cell_visible<=y>=grid_top&&row_needed!=0&&(row_needed==1||y<row_edge-row_gap)&&phase_x>={1'b0,width>>3};
  peak_visible<=y>=grid_top&&row_needed!=0&&y<row_edge-row_pitch+(row_gap!=0?row_gap:12'd1)&&phase_x>={1'b0,width>>3};
  peak_pipe<={peak_pipe[5:0],peak_visible&&peak_q!=0&&needed_q=={1'b0,peak_q}};
  lit_pipe<={lit_pipe[5:0],cell_visible&&{1'b0,band_q}>=needed_q};
  orange_pipe<={orange_pipe[5:0],needed_q=={1'b0,band_q}};
  {hs_out,vs_out,de_out}<=video[7][26:24];
  rgb_out<=enable_pipe[7]?(peak_pipe[6]?24'hff3030:lit_pipe[6]?(orange_pipe[6]?24'hff8800:24'hffdd00):24'h030810):video[7][23:0];
 end
endmodule
