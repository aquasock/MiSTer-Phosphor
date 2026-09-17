// Read-only 256-point radix-2 DIT FFT. L+jR packing keeps both channels,
// including opposite-phase stereo. Hann window, Q15 twiddles, 1/2 per stage.
// Acquisition pauses during analysis; playback has no ready/backpressure port.
module media_audio_fft(
 input wire clk,active,sample_tick,
 input wire signed [15:0] sample_left,sample_right,
 output reg [255:0] levels=0,output reg published=0
);
 (* ramstyle="M10K" *) reg [35:0] work[0:255];
 (* ramstyle="M10K" *) reg [15:0] window_rom[0:255];
 (* ramstyle="M10K" *) reg [31:0] twiddle_rom[0:127];
 reg [7:0] band_end[0:31];
 initial begin
  $readmemh("rtl/media_fft_window.hex",window_rom);
  $readmemh("rtl/media_fft_twiddle.hex",twiddle_rom);
  $readmemh("rtl/media_fft_band_end.hex",band_end);
 end
 reg [7:0] capture=0,rd_addr=0,base=0,half=1,tw_step=128,tw_index=0;
 reg [6:0] j=0,bin=1;
 reg [2:0] stage=0;
 reg [4:0] band=0;
 reg [7:0] end_bin=0,maximum=0;
 reg [247:0] building=0;
 reg [35:0] q=0;
 reg [15:0] window_q=0;
 reg [31:0] twiddle_q=0;
 always @(posedge clk)begin
  q<=work[rd_addr];window_q<=window_rom[capture];twiddle_q<=twiddle_rom[tw_index[6:0]];
  end_bin<=band_end[band];
 end
 wire [7:0] capture_address={capture[0],capture[1],capture[2],capture[3],capture[4],capture[5],capture[6],capture[7]};
 function automatic [17:0] absolute(input signed [17:0] v);
  absolute=v[17]?-v:v;
 endfunction
 function automatic [7:0] logarithm(input [19:0] value);
  reg [4:0] exponent;reg [3:0] normalized;reg [8:0] result;
  begin
   exponent=0;
   for(integer k=0;k<20;k=k+1)if(value[k])exponent=5'(k);
   normalized=4'((value<<4)>>exponent);
   result={exponent,4'b0}+{5'd0,normalized[3:0]};
   logarithm=value<8?8'd0:result>=303?8'd255:8'(result-48);
  end
 endfunction
 reg signed [15:0] left_q=0,right_q=0;
 reg signed [32:0] window_l=0,window_r=0;
 reg signed [17:0] ar=0,ai=0,br=0,bi=0;
 reg signed [33:0] p0=0,p1=0,p2=0,p3=0;
 reg signed [34:0] tr=0,ti=0;
 wire signed [18:0] sum_r={ar[17],ar}+19'(tr>>>15),sum_i={ai[17],ai}+19'(ti>>>15);
 wire signed [18:0] dif_r={ar[17],ar}-19'(tr>>>15),dif_i={ai[17],ai}-19'(ti>>>15);
 reg [19:0] magnitude=0;
 reg [7:0] value=0;
 wire [7:0] peak=value>maximum?value:maximum;
 localparam CAPTURE=0,WINDOW=1,STORE=2,INIT=3,RA=4,WA=5,LA=6,WB=7,LB=8,
  MUL=9,COMBINE=10,WRITE_A=11,WRITE_B=12,NEXT=13,
  BIN_RA=14,BIN_WA=15,BIN_LA=16,BIN_WB=17,BIN_LB=18,MAG=19,LOG=20,BAND=21;
 reg [4:0] state=CAPTURE;
 always @(posedge clk)begin
  published<=0;
  if(!active)begin
   state<=CAPTURE;capture<=0;levels<=0;building<=0;maximum<=0;band<=0;
  end else case(state)
   CAPTURE:if(sample_tick)begin left_q<=sample_left;right_q<=sample_right;state<=WINDOW;end
   WINDOW:begin window_l<=left_q*$signed({1'b0,window_q});window_r<=right_q*$signed({1'b0,window_q});state<=STORE;end
   STORE:begin
    work[capture_address]<={18'(window_l>>>15),18'(window_r>>>15)};
    capture<=capture+1'b1;state<=capture==255?INIT:CAPTURE;
   end
   INIT:begin stage<=0;half<=1;tw_step<=128;tw_index<=0;base<=0;j<=0;state<=RA;end
   RA:begin rd_addr<=base+{1'b0,j};state<=WA;end
   WA:state<=LA;
   LA:begin ar<=$signed(q[35:18]);ai<=$signed(q[17:0]);rd_addr<=base+{1'b0,j}+half;state<=WB;end
   WB:state<=LB;
   LB:begin br<=$signed(q[35:18]);bi<=$signed(q[17:0]);state<=MUL;end
   MUL:begin
    p0<=br*$signed(twiddle_q[31:16]);p1<=bi*$signed(twiddle_q[15:0]);
    p2<=br*$signed(twiddle_q[15:0]);p3<=bi*$signed(twiddle_q[31:16]);state<=COMBINE;
   end
   COMBINE:begin tr<={p0[33],p0}-{p1[33],p1};ti<={p2[33],p2}+{p3[33],p3};state<=WRITE_A;end
   WRITE_A:begin work[base+{1'b0,j}]<={18'(sum_r>>>1),18'(sum_i>>>1)};state<=WRITE_B;end
   WRITE_B:begin work[base+{1'b0,j}+half]<={18'(dif_r>>>1),18'(dif_i>>>1)};state<=NEXT;end
   NEXT:begin
    state<=RA;
    if({1'b0,j}+8'd1==half)begin
     j<=0;tw_index<=0;
     if({1'b0,base}+({1'b0,half}<<1)==256)begin
      base<=0;half<=half<<1;tw_step<=tw_step>>1;stage<=stage+1'b1;
      if(stage==7)begin bin<=1;band<=0;maximum<=0;state<=BIN_RA;end
     end else base<=base+(half<<1);
    end else begin j<=j+1'b1;tw_index<=tw_index+tw_step;end
   end
   BIN_RA:begin rd_addr<={1'b0,bin};state<=BIN_WA;end
   BIN_WA:state<=BIN_LA;
   BIN_LA:begin ar<=$signed(q[35:18]);ai<=$signed(q[17:0]);rd_addr<=8'd0-{1'b0,bin};state<=BIN_WB;end
   BIN_WB:state<=BIN_LB;
   BIN_LB:begin br<=$signed(q[35:18]);bi<=$signed(q[17:0]);state<=MAG;end
   MAG:begin magnitude<={2'd0,absolute(ar)}+{2'd0,absolute(ai)}+{2'd0,absolute(br)}+{2'd0,absolute(bi)};state<=LOG;end
   LOG:begin value<=logarithm(magnitude);state<=BAND;end
   BAND:begin
    if({1'b0,bin}==end_bin)begin
     building<={peak,building[247:8]};maximum<=0;band<=band+1'b1;
     if(band==31)begin levels<={peak,building};published<=1;state<=CAPTURE;end
     else begin bin<=bin+1'b1;state<=BIN_RA;end
    end else begin maximum<=peak;bin<=bin+1'b1;state<=BIN_RA;end
   end
   default:state<=CAPTURE;
  endcase
 end
endmodule
