// 256/2048-point Vorbis inverse MDCT. A zero-padded, pre-rotated inverse
// FFT computes the DCT-IV; the final signed quadrant mapping expands its
// 128/1024 values into the required 256/2048 time-domain samples.
module vorbis_imdct(
 input wire clk,input wire reset,
 input wire spectrum_valid,output wire spectrum_ready,input wire [9:0] spectrum_index,
 input wire signed [31:0] spectrum_value,
 input wire start,input wire long_block,
 output reg sample_valid=0,input wire sample_ready,output reg [10:0] sample_index=0,
 output reg signed [31:0] sample_value=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,PRE_READ=1,PRE_MUL=2,PRE_LOAD=3,FFT_START=4,FFT_WAIT=5,
  POST_REQ=6,POST_WAIT=7,POST_MUL=8,STREAM=9,FINISH=10,STREAM_WAIT=11,POST_STORE=12;
 // Preserve fractional precision through the FFT's per-stage normalization.
 // Six guard bits keep the 24-bit workspace safe for normal Vorbis spectra
 // while reducing long-block output quantization from 2048 counts to 32.
 localparam FFT_GUARD_BITS=6;
 reg [3:0] state=IDLE;reg saved_long=0;reg [10:0] m=0,length=0,index=0;
 reg [3:0] fft_log2=0;reg [10:0] rom_offset=0;
 (* ramstyle="M10K" *) reg signed [31:0] spectrum[0:1023];
 reg signed [31:0] spectrum_q=0;
 reg signed [23:0] fft_load_real=0,fft_load_imag=0;
 wire [71:0] rotation_q;
 wire signed [17:0] pre_r=rotation_q[71:54],pre_i=rotation_q[53:36];
 wire signed [17:0] post_r=rotation_q[35:18],post_i=rotation_q[17:0];
 reg signed [49:0] product_r=0,product_i=0;reg signed [63:0] scaled=0;
 wire fft_load_ready,fft_output_valid,fft_ready,fft_done,fft_error;
 wire signed [23:0] fft_output_real,fft_output_imag;
 wire fft_load_valid=state==PRE_LOAD;
 wire fft_start=state==FFT_START;
 wire fft_output_request=state==POST_REQ;
 wire [10:0] fft_load_address=bit_reverse(index,fft_log2);
 // The second half of the FFT input is explicit zero padding and does not
 // consume a rotation coefficient. Keep the physical ROM address in range
 // during those cycles instead of relying on an ignored out-of-range read.
 wire [10:0] rotation_address=rom_offset+(index<m?index:11'd0);
 vorbis_setup_ram #(.WIDTH(72),.DEPTH(1152),.ADDR_WIDTH(11),
  .INIT_FILE("rtl/audio/vorbis/vorbis_imdct_rotation.mif"),
  .SIM_INIT_FILE("rtl/audio/vorbis/vorbis_imdct_rotation.hex")) rotation_mem(clk,
  1'b0,11'd0,72'd0,rotation_address,rotation_q);
 assign ready=state==IDLE;
 assign spectrum_ready=state==IDLE&&!start;
 function [10:0] bit_reverse;input [10:0] value;input [3:0] bits;integer i;begin
  bit_reverse=0;for(i=0;i<11;i=i+1)if(i<bits)bit_reverse[bits-1-i]=value[i];
 end endfunction
 function signed [31:0] sat32;input signed [63:0] value;begin
  if(value>64'sh000000007fffffff)sat32=32'sh7fffffff;
  else if(value< -64'sh0000000080000000)sat32=32'sh80000000;
  else sat32=value[31:0];
 end endfunction
 function [9:0] dct_address;input [10:0] n;begin
  if(n<(m>>1))dct_address=(m>>1)+n;
  else if(n<(m+(m>>1)))dct_address=m+(m>>1)-1-n;
  else dct_address=n-(m+(m>>1));
 end endfunction
 function dct_negate;input [10:0] n;begin dct_negate=n>=(m>>1);end endfunction

 wire dct_write=state==POST_STORE;
 wire [31:0] dct_q;
 wire [9:0] dct_read_address=dct_address(index);
 vorbis_setup_ram #(.WIDTH(32),.DEPTH(1024),.ADDR_WIDTH(10)) dct(clk,
  dct_write,index[9:0],sat32(scaled),dct_read_address,dct_q);

 vorbis_fft fft(.clk(clk),.reset(reset),.load_valid(fft_load_valid),.load_ready(fft_load_ready),
  .load_address(fft_load_address),.load_real(fft_load_real),.load_imag(fft_load_imag),
  .start(fft_start),.length_log2(fft_log2),.output_request(fft_output_request),
  .output_address(index),.output_valid(fft_output_valid),.output_real(fft_output_real),
  .output_imag(fft_output_imag),.ready(fft_ready),.done(fft_done),.error(fft_error));

 always @(posedge clk)begin
  if(reset)begin state<=IDLE;sample_valid<=0;done<=0;error<=0;end
  else begin
   done<=0;if(sample_valid&&sample_ready)sample_valid<=0;if(fft_error)error<=1;
   if(state==IDLE&&spectrum_valid&&spectrum_ready)spectrum[spectrum_index]<=spectrum_value;
   case(state)
    IDLE:if(start)begin
     saved_long<=long_block;error<=0;index<=0;
     if(long_block)begin m<=1024;length<=2048;fft_log2<=11;rom_offset<=0;end
     else begin m<=128;length<=256;fft_log2<=8;rom_offset<=1024;end
     state<=PRE_READ;
    end
    PRE_READ:begin
     if(index<m)spectrum_q<=spectrum[index];
     state<=PRE_MUL;
    end
    PRE_MUL:begin
     if(index<m)begin
      product_r=$signed(spectrum_q)*$signed(pre_r);product_i=$signed(spectrum_q)*$signed(pre_i);
      fft_load_real<=(product_r>>>17)<<<FFT_GUARD_BITS;
      fft_load_imag<=(product_i>>>17)<<<FFT_GUARD_BITS;
     end else begin fft_load_real<=0;fft_load_imag<=0;end
     state<=PRE_LOAD;
    end
    PRE_LOAD:if(fft_load_ready)begin
     if(index+1'b1==length)state<=FFT_START;
     else begin index<=index+1'b1;state<=PRE_READ;end
    end
    FFT_START:begin index<=0;state<=FFT_WAIT;end
    FFT_WAIT:if(fft_done)state<=POST_REQ;
    POST_REQ:state<=POST_WAIT;
    POST_WAIT:if(fft_output_valid)state<=POST_MUL;
    POST_MUL:begin
     product_r=$signed(fft_output_real)*$signed(post_r)-$signed(fft_output_imag)*$signed(post_i);
     scaled=$signed(product_r>>>17)<<<(fft_log2-FFT_GUARD_BITS);
     state<=POST_STORE;
    end
    POST_STORE:begin
     if(index+1'b1==m)begin index<=0;sample_index<=0;state<=STREAM_WAIT;end
     else begin index<=index+1'b1;state<=POST_REQ;end
    end
    STREAM_WAIT:state<=STREAM;
    STREAM:if(!sample_valid||sample_ready)begin
     sample_index<=index;sample_value<=dct_negate(index)?-$signed(dct_q):$signed(dct_q);sample_valid<=1;
     if(index+1'b1==length)state<=FINISH;else index<=index+1'b1;
     if(index+1'b1!=length)state<=STREAM_WAIT;
    end
    FINISH:if(!sample_valid)begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
