// Native file decoder plus external frame storage. This block emits the
// format-independent PCM/EOF token stream; it does not generate an audio clock.
module flac_ddr_decoder #(
 parameter ENABLE_RESUME=0,
 parameter[28:0] BASE=29'h06080000
)(
 input wire clk,reset,cancel,start,
 input wire resume_frame,
 input wire [35:0] resume_sample,resume_total,
 input wire [15:0] resume_min_block,resume_max_block,
 output wire start_ready,quiescent,
 input wire[7:0] input_data,
 input wire input_valid,input_end,
 output wire input_ready,
 output wire metadata_valid,
 output wire[35:0] total_samples,
 output wire pcm_valid,pcm_eof,
 input wire pcm_ready,
 output wire signed[15:0] pcm_left,pcm_right,
 output wire[3:0] error,
 output wire[28:0] mem_addr,
 output wire[63:0] mem_data,
 output wire[7:0] mem_be,
 output wire mem_read,mem_write,
 input wire mem_busy,
 input wire[63:0] mem_q,
 input wire mem_q_valid
);
 reg decoder_active;
 wire begin_valid,begin_ready,sample_valid,sample_ready,sample_channel,commit_valid,commit_ready,finished,store_error;
 wire[15:0] frame_size,sample_index;wire[3:0] channel_assignment;
 wire signed[16:0] sample_data;
 wire[3:0] decoder_error;
 wire decoder_reset=reset||cancel||!decoder_active||(start&&start_ready);
 wire internal_input_ready;
 assign input_ready=internal_input_ready&&!cancel&&decoder_active;
 assign error=store_error?4'd8:decoder_error;
 always @(posedge clk)begin
  if(reset||cancel)decoder_active<=0;
  else if(start&&start_ready)decoder_active<=1;
 end
 flac_stream_decoder #(.ENABLE_RESUME(ENABLE_RESUME)) decoder(.clk(clk),.reset(decoder_reset),
  .resume_frame(resume_frame),.resume_sample(resume_sample),.resume_total(resume_total),
  .resume_min_block(resume_min_block),.resume_max_block(resume_max_block),
  .input_data(input_data),.input_valid(input_valid),.input_end(input_end),.input_ready(internal_input_ready),
  .metadata_valid(metadata_valid),.total_samples(total_samples),
  .begin_valid(begin_valid),.begin_ready(begin_ready),.frame_size(frame_size),.channel_assignment(channel_assignment),.frame_position(),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_channel(sample_channel),.sample_index(sample_index),.sample_data(sample_data),
  .commit_valid(commit_valid),.commit_ready(commit_ready),.store_error(store_error),.finished(finished),.error(decoder_error));
 flac_frame_store #(.BASE(BASE)) store(.clk(clk),.reset(reset),.cancel(cancel),.start(start),.start_ready(start_ready),.quiescent(quiescent),
  .begin_valid(begin_valid),.begin_ready(begin_ready),.frame_size(frame_size),.channel_assignment(channel_assignment),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_channel(sample_channel),.sample_index(sample_index),.sample_data(sample_data),
  .commit_valid(commit_valid),.commit_ready(commit_ready),.input_finished(finished),
  .pcm_valid(pcm_valid),.pcm_ready(pcm_ready),.pcm_eof(pcm_eof),.pcm_left(pcm_left),.pcm_right(pcm_right),.error(store_error),
  .mem_addr(mem_addr),.mem_data(mem_data),.mem_be(mem_be),.mem_read(mem_read),.mem_write(mem_write),.mem_busy(mem_busy),.mem_q(mem_q),.mem_q_valid(mem_q_valid));
endmodule
