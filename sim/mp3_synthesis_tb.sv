// Streams a real MP3 file through the full pipeline -- mp3_frame_parser
// -> mp3_bit_reservoir -> mp3_huffman_decoder -> mp3_dequant -> mp3_stereo
// -> mp3_antialias -> mp3_imdct -> mp3_synthesis -- dumping every final
// PCM sample for comparison against tools/mp3_synthesis_reference.py by
// sim/compare_synthesis.py.
`timescale 1ns/1ps
module mp3_synthesis_tb;

parameter HEX_FILE = "";
parameter NUM_FRAMES = 2;
parameter BUF_LOG2 = 11;

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg [7:0] mem_in [0:299999];
initial $readmemh(HEX_FILE, mem_in);

integer idx;
wire input_ready;
// mp3_synthesis's own per-time-slot processing (~64*32 matrixing MACs +
// 32*16 windowing MACs, ~3,100 serial cycles) makes it slower still than
// mp3_imdct per unit of channel data -- the same real-bit-rate-pacing
// discipline established there applies here too, extended to also gate
// on this module's own idle state.
reg frame_pending = 0;
reg frame_done_seen = 0;
wire downstream_idle = (stereo_dut.state == 0) && (stereo_dut.q_count == 0) &&
                        (aa_dut.state == 0) && (aa_dut.q_count == 0) &&
                        (imdct_dut.state == 0) && (imdct_dut.q_count == 0) &&
                        (synth_dut.state == 0) && (synth_dut.q_count == 0);
always @(posedge clk) begin
    if (reset) begin
        frame_pending <= 0;
        frame_done_seen <= 0;
    end else if (frame_valid) begin
        frame_pending <= 1;
        frame_done_seen <= 0;
    end else if (frame_done) begin
        frame_done_seen <= 1;
    end else if (frame_pending && frame_done_seen && downstream_idle) begin
        frame_pending <= 0;
    end
end
wire input_valid = !frame_pending && (frame_count < NUM_FRAMES);
wire [7:0] input_data = mem_in[idx];

always @(posedge clk) begin
    if (reset) idx <= 0;
    else if (input_valid && input_ready) idx <= idx + 1;
end

wire frame_valid, stereo, sample_rate_44k1;
wire [1:0] channel_mode, mode_extension;
wire [9:0] frame_len;
wire [8:0] main_data_begin;
wire main_data_valid, main_data_start;
wire [7:0] main_data_byte;

wire scfsi_flat [0:1][0:3];
wire [11:0] part2_3_length [0:3];
wire [8:0] big_values [0:3];
wire [7:0] global_gain [0:3];
wire [3:0] scalefac_compress [0:3];
wire window_switching_flag [0:3];
wire [1:0] block_type [0:3];
wire mixed_block_flag [0:3];
wire [4:0] table_select [0:3][0:2];
wire [2:0] subblock_gain [0:3][0:2];
wire [3:0] region0_count [0:3];
wire [2:0] region1_count [0:3];
wire preflag [0:3];
wire scalefac_scale [0:3];
wire count1table_select [0:3];

mp3_frame_parser parser (
    .clk(clk), .reset(reset),
    .input_data(input_data), .input_valid(input_valid), .input_ready(input_ready),
    .frame_valid(frame_valid), .stereo(stereo),
    .channel_mode(channel_mode), .mode_extension(mode_extension),
    .frame_len(frame_len), .main_data_begin(main_data_begin),
    .sample_rate_44k1(sample_rate_44k1),
    .scfsi(scfsi_flat),
    .part2_3_length(part2_3_length), .big_values(big_values), .global_gain(global_gain),
    .scalefac_compress(scalefac_compress), .window_switching_flag(window_switching_flag),
    .block_type(block_type), .mixed_block_flag(mixed_block_flag),
    .table_select(table_select), .subblock_gain(subblock_gain),
    .region0_count(region0_count), .region1_count(region1_count),
    .preflag(preflag), .scalefac_scale(scalefac_scale), .count1table_select(count1table_select),
    .main_data_valid(main_data_valid), .main_data_byte(main_data_byte),
    .main_data_start(main_data_start)
);

wire [10:0] frame_read_start;
wire [10:0] resv_read_addr;
wire [7:0] resv_read_data;

mp3_bit_reservoir #(.BUFFER_BYTES_LOG2(BUF_LOG2)) resv (
    .clk(clk), .reset(reset),
    .main_data_valid(main_data_valid), .main_data_byte(main_data_byte),
    .main_data_start(main_data_start), .main_data_begin(main_data_begin),
    .frame_read_start(frame_read_start),
    .read_addr(resv_read_addr), .read_data(resv_read_data)
);

wire sf_valid;
wire [1:0] sf_gci;
wire [5:0] sf_index;
wire [3:0] sf_data;
wire value_valid;
wire [1:0] value_gci;
wire [9:0] value_index;
wire signed [15:0] value_data;
wire gc_done;
wire [1:0] gc_done_index;
wire frame_done;

mp3_huffman_decoder huff (
    .clk(clk), .reset(reset),
    .frame_valid(frame_valid), .stereo(stereo), .sample_rate_44k1(sample_rate_44k1),
    .scfsi(scfsi_flat),
    .part2_3_length(part2_3_length), .big_values(big_values),
    .scalefac_compress(scalefac_compress), .window_switching_flag(window_switching_flag),
    .block_type(block_type), .mixed_block_flag(mixed_block_flag),
    .table_select(table_select),
    .region0_count(region0_count), .region1_count(region1_count),
    .count1table_select(count1table_select),
    .frame_read_start(frame_read_start),
    .read_addr(resv_read_addr), .read_data(resv_read_data),
    .sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
    .value_valid(value_valid), .value_gci(value_gci), .value_index(value_index), .value_data(value_data),
    .gc_done(gc_done), .gc_done_index(gc_done_index), .frame_done(frame_done)
);

wire dq_valid;
wire [1:0] dq_gci;
wire [9:0] dq_index;
wire signed [31:0] dq_data;

mp3_dequant dequant (
    .clk(clk), .reset(reset),
    .frame_valid(frame_valid), .sample_rate_44k1(sample_rate_44k1),
    .window_switching_flag(window_switching_flag), .block_type(block_type),
    .mixed_block_flag(mixed_block_flag), .global_gain(global_gain),
    .scalefac_scale(scalefac_scale), .preflag(preflag), .subblock_gain(subblock_gain),
    .sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
    .value_valid(value_valid), .value_gci(value_gci), .value_index(value_index), .value_data(value_data),
    .out_valid(dq_valid), .out_gci(dq_gci), .out_index(dq_index), .out_data(dq_data)
);

wire st_valid;
wire [1:0] st_gci;
wire [9:0] st_index;
wire signed [31:0] st_data;
wire st_wsf;
wire [1:0] st_bt;
wire st_mbf;

mp3_stereo stereo_dut (
    .clk(clk), .reset(reset),
    .frame_valid(frame_valid), .stereo(stereo), .mode_extension(mode_extension),
    .sample_rate_44k1(sample_rate_44k1),
    .window_switching_flag(window_switching_flag), .block_type(block_type),
    .mixed_block_flag(mixed_block_flag),
    .sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
    .value_valid(dq_valid), .value_gci(dq_gci), .value_index(dq_index), .value_data(dq_data),
    .out_valid(st_valid), .out_gci(st_gci), .out_index(st_index), .out_data(st_data),
    .out_wsf(st_wsf), .out_bt(st_bt), .out_mbf(st_mbf)
);

wire aa_valid;
wire [1:0] aa_gci;
wire [9:0] aa_index;
wire signed [31:0] aa_data;
wire aa_wsf;
wire [1:0] aa_bt;
wire aa_mbf;

mp3_antialias aa_dut (
    .clk(clk), .reset(reset),
    .value_valid(st_valid), .value_gci(st_gci), .value_index(st_index), .value_data(st_data),
    .value_wsf(st_wsf), .value_bt(st_bt), .value_mbf(st_mbf),
    .out_valid(aa_valid), .out_gci(aa_gci), .out_index(aa_index), .out_data(aa_data),
    .out_wsf(aa_wsf), .out_bt(aa_bt), .out_mbf(aa_mbf)
);

wire imdct_valid;
wire [1:0] imdct_gci;
wire [9:0] imdct_index;
wire signed [31:0] imdct_data;

mp3_imdct imdct_dut (
    .clk(clk), .reset(reset),
    .value_valid(aa_valid), .value_gci(aa_gci), .value_index(aa_index), .value_data(aa_data),
    .value_wsf(aa_wsf), .value_bt(aa_bt), .value_mbf(aa_mbf),
    .out_valid(imdct_valid), .out_gci(imdct_gci), .out_index(imdct_index), .out_data(imdct_data)
);

wire out_valid;
wire [1:0] out_gci;
wire [4:0] out_sample;
wire signed [15:0] out_data;

mp3_synthesis synth_dut (
    .clk(clk), .reset(reset),
    .value_valid(imdct_valid), .value_gci(imdct_gci), .value_index(imdct_index), .value_data(imdct_data),
    .out_valid(out_valid), .out_gci(out_gci), .out_sample(out_sample), .out_data(out_data)
);

initial begin
    #12 reset = 0;
end

integer frame_count = 0;
integer synth_count [0:3];
initial begin
    synth_count[0] = 0; synth_count[1] = 0; synth_count[2] = 0; synth_count[3] = 0;
end

always @(posedge clk) begin
    if (out_valid) begin
        $display("PCM gci=%0d idx=%0d data=%0d", out_gci, synth_count[out_gci], out_data);
        if (synth_count[out_gci] == 575) begin
            $display("PCMDONE gci=%0d", out_gci);
            synth_count[out_gci] <= 0;
        end else begin
            synth_count[out_gci] <= synth_count[out_gci] + 1;
        end
    end
    if (frame_done) begin
        frame_count <= frame_count + 1;
        $display("FRAMEDONE %0d", frame_count + 1);
    end
end

// mp3_synthesis's own processing (~3,100 serial MAC cycles per time slot,
// 18 time slots/channel) makes it slower still than mp3_imdct -- the
// drain after the last frame needs to be correspondingly generous. Kept
// in its own block for the same reason as every earlier testbench here.
//
// frame_count >= NUM_FRAMES - 1 (not >= NUM_FRAMES): frame_count is
// incremented via a NONBLOCKING assignment in a separate always block
// (the one that also prints FRAMEDONE), so this block sees its PRE-
// increment value on the same edge frame_done pulses for the Nth frame --
// checking >= NUM_FRAMES here would never be true (frame_count never
// reaches NUM_FRAMES before input_valid stops admitting new frames), so
// this drain path silently never fired and every run fell through to the
// much longer outer safety timeout instead. Same bug, same fix needed,
// in mp3_dequant_tb.sv/mp3_stereo_tb.sv/mp3_antialias_tb.sv/
// mp3_imdct_tb.sv (all copy the same pattern) -- not fixed there yet
// since it doesn't affect correctness, only wasted wall-clock time.
always @(posedge clk) begin
    if (frame_done && frame_count >= NUM_FRAMES - 1) begin
        #60000000 $finish;
    end
end

initial begin
    #2000000000 begin
        $display("TIMEOUT waiting for %0d frames, got %0d", NUM_FRAMES, frame_count);
        $finish;
    end
end

endmodule
