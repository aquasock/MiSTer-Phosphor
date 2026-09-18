// Shared-transform stereo synthesis. Spectra are read from the interleaved
// residue workspace one channel at a time, transformed, windowed with separate
// channel histories, then reunited into synchronized PCM pairs.
module vorbis_synthesis(
 input wire clk,input wire reset,input wire start,
 input wire long_block,input wire previous_short,input wire next_short,input wire [10:0] spectral_bins,
 output reg workspace_read_valid=0,input wire workspace_read_ready,
 output reg [11:0] workspace_read_address=0,input wire workspace_read_data_valid,
 input wire signed [31:0] workspace_read_data,
 output reg pcm_valid=0,input wire pcm_ready,output reg [10:0] pcm_index=0,
 output reg signed [31:0] pcm_left=0,output reg signed [31:0] pcm_right=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,WIN_START=1,READ_REQ=2,READ_WAIT=3,SPEC_SEND=4,
  IMDCT_START=5,RUN=6,NEXT_CHANNEL=7,FINISH=8;
 reg [3:0] state=IDLE;reg channel=0;reg [10:0] spectrum_index=0;
 reg saved_long=0,saved_previous_short=0,saved_next_short=0;reg [10:0] saved_bins=0;
 reg signed [31:0] spectrum_value=0;
 reg imdct_spectrum_valid=0,imdct_start=0,win0_start=0,win1_start=0;
 wire imdct_spectrum_ready,imdct_sample_valid,imdct_sample_ready,imdct_ready,imdct_done,imdct_error;
 wire [10:0] imdct_sample_index;wire signed [31:0] imdct_sample_value;
 wire win0_sample_ready,win1_sample_ready,win0_pcm_valid,win1_pcm_valid;
 wire [10:0] win0_pcm_index,win1_pcm_index;wire signed [31:0] win0_pcm_value,win1_pcm_value;
 wire win0_ready,win1_ready,win0_done,win1_done,win0_error,win1_error;
 reg win_done_seen=0,imdct_done_seen=0;
 (* ramstyle="M10K" *) reg signed [31:0] left_pcm[0:1023];
 reg [1:0] pair_state=0;reg signed [31:0] left_q=0,saved_right=0;reg [10:0] saved_pcm_index=0;
 wire win1_pcm_ready=pair_state==0&&!pcm_valid;
 assign ready=state==IDLE;
 assign imdct_sample_ready=channel?win1_sample_ready:win0_sample_ready;

 vorbis_imdct imdct(.clk(clk),.reset(reset),.spectrum_valid(imdct_spectrum_valid),
  .spectrum_ready(imdct_spectrum_ready),.spectrum_index(spectrum_index[9:0]),.spectrum_value(spectrum_value),
  .start(imdct_start),.long_block(saved_long),.sample_valid(imdct_sample_valid),
  .sample_ready(imdct_sample_ready),.sample_index(imdct_sample_index),.sample_value(imdct_sample_value),
  .ready(imdct_ready),.done(imdct_done),.error(imdct_error));
 vorbis_window_overlap window_left(.clk(clk),.reset(reset),.block_start(win0_start),
  .long_block(saved_long),.previous_short(saved_previous_short),.next_short(saved_next_short),
  .sample_valid(imdct_sample_valid&&!channel),.sample_ready(win0_sample_ready),
  .sample_index(imdct_sample_index),.sample_value(imdct_sample_value),
  .pcm_valid(win0_pcm_valid),.pcm_ready(1'b1),.pcm_index(win0_pcm_index),.pcm_value(win0_pcm_value),
  .ready(win0_ready),.done(win0_done),.error(win0_error));
 vorbis_window_overlap window_right(.clk(clk),.reset(reset),.block_start(win1_start),
  .long_block(saved_long),.previous_short(saved_previous_short),.next_short(saved_next_short),
  .sample_valid(imdct_sample_valid&&channel),.sample_ready(win1_sample_ready),
  .sample_index(imdct_sample_index),.sample_value(imdct_sample_value),
  .pcm_valid(win1_pcm_valid),.pcm_ready(win1_pcm_ready),.pcm_index(win1_pcm_index),.pcm_value(win1_pcm_value),
  .ready(win1_ready),.done(win1_done),.error(win1_error));

 always @(posedge clk)begin
  if(reset)begin pair_state<=0;pcm_valid<=0;end
  else begin
   if(pcm_valid&&pcm_ready)pcm_valid<=0;
   if(win0_pcm_valid)left_pcm[win0_pcm_index]<=win0_pcm_value;
   case(pair_state)
    0:if(win1_pcm_valid&&win1_pcm_ready)begin
     left_q<=left_pcm[win1_pcm_index];saved_right<=win1_pcm_value;saved_pcm_index<=win1_pcm_index;pair_state<=1;
    end
    1:begin pcm_index<=saved_pcm_index;pcm_left<=left_q;pcm_right<=saved_right;pcm_valid<=1;pair_state<=2;end
    2:if(pcm_valid&&pcm_ready)pair_state<=0;
   endcase
  end
 end

 always @(posedge clk)begin
  if(reset)begin state<=IDLE;workspace_read_valid<=0;imdct_spectrum_valid<=0;imdct_start<=0;
   win0_start<=0;win1_start<=0;done<=0;error<=0;channel<=0;end
  else begin
   done<=0;imdct_start<=0;win0_start<=0;win1_start<=0;
   if(imdct_error||win0_error||win1_error)error<=1;
   if(imdct_done)imdct_done_seen<=1;
   if((channel?win1_done:win0_done))win_done_seen<=1;
   case(state)
    IDLE:if(start)begin
     error<=0;channel<=0;spectrum_index<=0;imdct_done_seen<=0;win_done_seen<=0;
     saved_long<=long_block;saved_previous_short<=previous_short;saved_next_short<=next_short;saved_bins<=spectral_bins;
     state<=WIN_START;
    end
    WIN_START:if(channel?win1_ready:win0_ready)begin
     if(channel)win1_start<=1;else win0_start<=1;
     state<=READ_REQ;
    end
    READ_REQ:if(workspace_read_ready)begin
     workspace_read_address<=spectrum_index*2+channel;workspace_read_valid<=1;state<=READ_WAIT;
    end
    READ_WAIT:begin workspace_read_valid<=0;if(workspace_read_data_valid)begin spectrum_value<=workspace_read_data;state<=SPEC_SEND;end end
    SPEC_SEND:begin
     imdct_spectrum_valid<=1;
     if(imdct_spectrum_valid&&imdct_spectrum_ready)begin
      imdct_spectrum_valid<=0;
      if(spectrum_index+1'b1==saved_bins)state<=IMDCT_START;
      else begin spectrum_index<=spectrum_index+1'b1;state<=READ_REQ;end
     end
    end
    IMDCT_START:if(imdct_ready)begin imdct_start<=1;imdct_done_seen<=0;win_done_seen<=0;state<=RUN;end
    RUN:if((imdct_done_seen||imdct_done)&&(win_done_seen||(channel?win1_done:win0_done)))state<=NEXT_CHANNEL;
    NEXT_CHANNEL:begin
     if(!channel)begin channel<=1;spectrum_index<=0;imdct_done_seen<=0;win_done_seen<=0;state<=WIN_START;end
     else if(pair_state==0&&!pcm_valid)state<=FINISH;
    end
    FINISH:begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
