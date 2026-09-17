// Integration-style testbench: replicates MiSTer_MP3.sv's real sniff ->
// replay -> flac_start/flac_started sequencing (not just flac_ddr_decoder
// standalone, which sim/flac_ddr_decoder_tb.sv already covers) to validate
// the replay-gating fix before asking for another real-hardware round trip.
// Feeds a real FLAC file starting from true byte 0, exactly as the file
// reader would, through the same sniff/replay logic as the real top level.
`timescale 1ns/1ps
module flac_dispatch_tb;

parameter HEX_FILE = "";

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg [7:0] file_mem [0:9999999];
initial $readmemh(HEX_FILE, file_mem);
integer total_bytes = 0;
initial while (file_mem[total_bytes] !== 8'hxx && total_bytes < 10000000) total_bytes = total_bytes + 1;

integer file_idx = 0;
wire stream_valid = (file_idx < total_bytes);
wire [8:0] stream_data = (file_idx < total_bytes) ? {1'b0, file_mem[file_idx]} : 9'h100;
wire stream_ready;
always @(posedge clk) begin
    if (reset) file_idx <= 0;
    else if (stream_valid && stream_ready) file_idx <= file_idx + 1;
end

// -- Sniff + replay, copied from MiSTer_MP3.sv (fixed version) -----------
localparam FMT_MP3 = 2'd0, FMT_WAV = 2'd1, FMT_FLAC = 2'd2;
reg [1:0] format_mode;
reg [7:0] sniff_buf [0:3];
reg [2:0] sniff_count;
reg [2:0] replay_count;
wire sniffing  = sniff_count < 3'd4;
wire replaying = !sniffing && replay_count < 3'd4;
wire format_committed = !sniffing;
wire flac_active = format_committed && (format_mode == FMT_FLAC);
wire flac_input_ready;
wire active_input_ready = flac_active ? flac_input_ready : 1'b0;

always @(posedge clk) begin
    if (reset) begin
        sniff_count  <= 3'd0;
        replay_count <= 3'd0;
        format_mode  <= FMT_MP3;
    end else if (sniffing) begin
        if (stream_valid && !stream_data[8]) begin
            sniff_buf[sniff_count[1:0]] <= stream_data[7:0];
            sniff_count <= sniff_count + 3'd1;
            if (sniff_count == 3'd3) begin
                if (sniff_buf[0] == 8'h66 && sniff_buf[1] == 8'h4C &&
                    sniff_buf[2] == 8'h61 && stream_data[7:0] == 8'h43)
                    format_mode <= FMT_FLAC;
                else
                    format_mode <= FMT_MP3;
            end
        end
    end else if (replaying) begin
        if (active_input_ready) replay_count <= replay_count + 3'd1;
    end
end

wire [7:0] decoder_stream_data  = replaying ? sniff_buf[replay_count[1:0]] : stream_data[7:0];
wire       decoder_stream_valid = sniffing  ? 1'b0 :
                                   replaying ? 1'b1 :
                                   (stream_valid && !stream_data[8]);
wire       decoder_stream_eof   = format_committed && !replaying && stream_data[8];
wire flac_input_valid = flac_active && decoder_stream_valid;
wire flac_stream_ready = decoder_stream_eof ? 1'b1 : flac_input_ready;
assign stream_ready = sniffing ? 1'b1 : replaying ? 1'b0 : flac_active ? flac_stream_ready : 1'b0;

wire flac_cancel = !flac_active;
reg flac_started;
always @(posedge clk) begin
    if (reset || !flac_active) flac_started <= 1'b0;
    else flac_started <= 1'b1;
end
wire flac_start = flac_active && !flac_started;

reg flac_eof_seen;
always @(posedge clk) begin
    if (reset || !flac_active) flac_eof_seen <= 1'b0;
    else if (decoder_stream_eof) flac_eof_seen <= 1'b1;
end

// -- Behavioral DDR model, same as sim/flac_ddr_decoder_tb.sv ------------
localparam [28:0] BASE = 29'h06080000;
reg [63:0] ddr_mem [0:131071];
reg [2:0] ddr_wait;
reg ddr_busy_r, ddr_is_read;
reg [16:0] ddr_offset_latched;
reg [63:0] ddr_q_r;
reg ddr_q_valid_r;
wire [28:0] mem_addr;
wire [63:0] mem_data;
wire [7:0] mem_be;
wire mem_read, mem_write;
wire [16:0] ddr_offset = mem_addr[16:0];

always @(posedge clk) begin
    ddr_q_valid_r <= 1'b0;
    if (reset) begin
        ddr_busy_r <= 1'b0;
        ddr_wait <= 3'd0;
    end else if (!ddr_busy_r) begin
        if (mem_read || mem_write) begin
            ddr_busy_r <= 1'b1;
            ddr_wait <= 3'd3;
            ddr_is_read <= mem_read;
            ddr_offset_latched <= ddr_offset;
        end
    end else if (ddr_wait != 3'd0) begin
        ddr_wait <= ddr_wait - 3'd1;
    end else begin
        ddr_busy_r <= 1'b0;
        if (ddr_is_read) begin
            ddr_q_r <= ddr_mem[ddr_offset_latched];
            ddr_q_valid_r <= 1'b1;
        end
    end
end
reg [63:0] wr_data_latched;
reg [7:0] wr_be_latched;
always @(posedge clk) if (!reset && !ddr_busy_r && mem_write) begin wr_data_latched <= mem_data; wr_be_latched <= mem_be; end
always @(posedge clk) if (!reset && ddr_busy_r && ddr_wait == 3'd0 && !ddr_is_read) begin
    if (wr_be_latched[0]) ddr_mem[ddr_offset_latched][7:0]   <= wr_data_latched[7:0];
    if (wr_be_latched[1]) ddr_mem[ddr_offset_latched][15:8]  <= wr_data_latched[15:8];
    if (wr_be_latched[2]) ddr_mem[ddr_offset_latched][23:16] <= wr_data_latched[23:16];
    if (wr_be_latched[3]) ddr_mem[ddr_offset_latched][31:24] <= wr_data_latched[31:24];
    if (wr_be_latched[4]) ddr_mem[ddr_offset_latched][39:32] <= wr_data_latched[39:32];
    if (wr_be_latched[5]) ddr_mem[ddr_offset_latched][47:40] <= wr_data_latched[47:40];
    if (wr_be_latched[6]) ddr_mem[ddr_offset_latched][55:48] <= wr_data_latched[55:48];
    if (wr_be_latched[7]) ddr_mem[ddr_offset_latched][63:56] <= wr_data_latched[63:56];
end

wire pcm_valid, pcm_eof;
reg pcm_ready = 1'b1;
wire signed [15:0] pcm_left, pcm_right;
wire [3:0] error;

flac_ddr_decoder #(.ENABLE_RESUME(0), .BASE(BASE)) dut (
    .clk(clk), .reset(reset), .cancel(flac_cancel), .start(flac_start),
    .resume_frame(1'b0), .resume_sample(36'd0), .resume_total(36'd0),
    .resume_min_block(16'd0), .resume_max_block(16'd0),
    .start_ready(), .quiescent(),
    .input_data(decoder_stream_data), .input_valid(flac_input_valid), .input_end(flac_eof_seen), .input_ready(flac_input_ready),
    .metadata_valid(), .total_samples(),
    .pcm_valid(pcm_valid), .pcm_eof(pcm_eof), .pcm_ready(pcm_ready),
    .pcm_left(pcm_left), .pcm_right(pcm_right), .error(error),
    .mem_addr(mem_addr), .mem_data(mem_data), .mem_be(mem_be),
    .mem_read(mem_read), .mem_write(mem_write), .mem_busy(ddr_busy_r),
    .mem_q(ddr_q_r), .mem_q_valid(ddr_q_valid_r)
);

integer sample_count = 0;
reg saw_eof = 0, saw_error = 0;
always @(posedge clk) begin
    if (!reset && pcm_valid && pcm_ready) begin
        $display("PCM idx=%0d left=%0d right=%0d eof=%0d", sample_count, pcm_left, pcm_right, pcm_eof);
        sample_count <= sample_count + 1;
        if (pcm_eof) saw_eof <= 1;
    end
    if (!reset && error != 0 && !saw_error) begin
        $display("ERROR error=%0d at sample %0d format_mode=%0d", error, sample_count, format_mode);
        saw_error <= 1;
    end
end

initial begin
    #12 reset = 0;
end

always @(posedge clk) begin
    if (saw_eof || saw_error) begin
        $display("RESULT: %s, %0d samples", saw_error ? "ERROR" : "DONE", sample_count);
        #200 $finish;
    end
end

initial begin
    #2000000000 begin
        $display("TIMEOUT after %0d samples", sample_count);
        $finish;
    end
end

endmodule
