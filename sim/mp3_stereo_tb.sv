// Streams a real MP3 file through the full pipeline built so far --
// mp3_frame_parser -> mp3_bit_reservoir -> mp3_huffman_decoder ->
// mp3_dequant -> mp3_stereo -- dumping every final spectral value for
// comparison against tools/mp3_stereo_reference.py by sim/compare_stereo.py.
`timescale 1ns/1ps
module mp3_stereo_tb;

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
reg frame_pending = 0;
always @(posedge clk) begin
    if (reset) frame_pending <= 0;
    else if (frame_valid) frame_pending <= 1;
    else if (frame_done) frame_pending <= 0;
end
wire input_valid = !frame_pending;
wire [7:0] input_data = mem_in[idx];

always @(posedge clk) begin
    if (reset) idx <= 0;
    else if (input_valid && input_ready) idx <= idx + 1;
end

wire frame_valid, stereo;
wire [1:0] sr_idx;
wire [1:0] channel_mode, mode_extension;
wire [10:0] frame_len;
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
    .sr_idx(sr_idx),
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
    .frame_valid(frame_valid), .stereo(stereo), .sr_idx(sr_idx),
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
    .frame_valid(frame_valid), .sr_idx(sr_idx),
    .window_switching_flag(window_switching_flag), .block_type(block_type),
    .mixed_block_flag(mixed_block_flag), .global_gain(global_gain),
    .scalefac_scale(scalefac_scale), .preflag(preflag), .subblock_gain(subblock_gain),
    .sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
    .value_valid(value_valid), .value_gci(value_gci), .value_index(value_index), .value_data(value_data),
    .out_valid(dq_valid), .out_gci(dq_gci), .out_index(dq_index), .out_data(dq_data)
);

wire out_valid;
wire [1:0] out_gci;
wire [9:0] out_index;
wire signed [31:0] out_data;

mp3_stereo stereo_dut (
    .clk(clk), .reset(reset),
    .frame_valid(frame_valid), .stereo(stereo), .mode_extension(mode_extension),
    .sr_idx(sr_idx),
    .window_switching_flag(window_switching_flag), .block_type(block_type),
    .mixed_block_flag(mixed_block_flag),
    .sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
    .value_valid(dq_valid), .value_gci(dq_gci), .value_index(dq_index), .value_data(dq_data),
    .out_valid(out_valid), .out_gci(out_gci), .out_index(out_index), .out_data(out_data)
);

initial begin
    #12 reset = 0;
end

integer frame_count = 0;

always @(posedge clk) begin
    if (out_valid) begin
        $display("ST gci=%0d idx=%0d data=%0d", out_gci, out_index, out_data);
        if (out_index == 10'd575) $display("STDONE gci=%0d", out_gci);
    end
    if (frame_done) begin
        frame_count <= frame_count + 1;
        $display("FRAMEDONE %0d", frame_count + 1);
    end
end

// mp3_stereo buffers and processes a whole granule pair before emitting
// anything, and can lag frame_done by a substantial backlog (up to two
// pairs' worth of scan+reorder+stream time) -- a much bigger drain than
// mp3_dequant's few-cycle pipeline needed. Kept in its own block for the
// same reason as mp3_dequant_tb.sv: a blocking delay sharing a block with
// the monitor above would miss any ST/STDONE events that arrive during it.
always @(posedge clk) begin
    if (frame_done && frame_count >= NUM_FRAMES) begin
        #2000000 $finish;
    end
end

initial begin
    #400000000 begin
        $display("TIMEOUT waiting for %0d frames, got %0d", NUM_FRAMES, frame_count);
        $finish;
    end
end

endmodule
