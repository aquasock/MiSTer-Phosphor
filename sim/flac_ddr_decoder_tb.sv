// Standalone testbench for flac_ddr_decoder.sv (reused verbatim from
// MiSTer-Phosphor) -- this RTL has never been simulated anywhere before,
// in Phosphor or here, despite docs/FLAC.md describing it as verified.
// Same process-gap lesson as this project's own mp3_pcm_pack.sv: write a
// real testbench before trusting reused RTL, regardless of how confident
// the source project's own documentation sounds.
//
// Includes a small behavioral DDR model (a handful of cycles of latency on
// every read/write, not a real timing model) since Icarus can't simulate
// the real Cyclone V DDR3 controller -- matching this project's established
// pattern for every other un-simulatable Altera primitive (dcfifo, PLLs):
// simulate everything *around* the primitive for real, stub only the
// primitive itself.
`timescale 1ns/1ps
module flac_ddr_decoder_tb;

parameter HEX_FILE = "";

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg [7:0] mem_in [0:9999999];
integer file_len;
initial begin
    $readmemh(HEX_FILE, mem_in);
end

integer idx = 0;
integer total_bytes = 0;
initial begin
    // $readmemh doesn't report how many words it read; count non-x entries
    // up front so input_end can be driven off the real file length rather
    // than a guessed sentinel.
    while (mem_in[total_bytes] !== 8'hxx && total_bytes < 10000000) total_bytes = total_bytes + 1;
end

wire input_ready;
wire input_valid = (idx < total_bytes);
wire input_end = (idx >= total_bytes);
wire [7:0] input_data = mem_in[idx];

always @(posedge clk) begin
    if (reset) idx <= 0;
    else if (input_valid && input_ready) idx <= idx + 1;
end

// -- Behavioral DDR model -------------------------------------------------
localparam [28:0] BASE = 29'h06080000;
localparam DDR_LATENCY = 3;
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
wire [16:0] ddr_offset = mem_addr[16:0]; // BASE + offset, offset < 131072 = 2^17

always @(posedge clk) begin
    ddr_q_valid_r <= 1'b0;
    if (reset) begin
        ddr_busy_r <= 1'b0;
        ddr_wait <= 3'd0;
    end else if (!ddr_busy_r) begin
        if (mem_read || mem_write) begin
            ddr_busy_r <= 1'b1;
            ddr_wait <= DDR_LATENCY[2:0];
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

// Write applied combinationally with the *latched* address/data at the
// moment the busy countdown completes -- mem_data/mem_be themselves are
// only guaranteed stable for the single cycle mem_write pulses, so latch
// them alongside the offset rather than re-reading the live bus later.
reg [63:0] wr_data_latched;
reg [7:0] wr_be_latched;
always @(posedge clk) begin
    if (!reset && !ddr_busy_r && mem_write) begin
        wr_data_latched <= mem_data;
        wr_be_latched   <= mem_be;
    end
end
always @(posedge clk) begin
    if (!reset && ddr_busy_r && ddr_wait == 3'd0 && !ddr_is_read) begin
        if (wr_be_latched[0]) ddr_mem[ddr_offset_latched][7:0]   <= wr_data_latched[7:0];
        if (wr_be_latched[1]) ddr_mem[ddr_offset_latched][15:8]  <= wr_data_latched[15:8];
        if (wr_be_latched[2]) ddr_mem[ddr_offset_latched][23:16] <= wr_data_latched[23:16];
        if (wr_be_latched[3]) ddr_mem[ddr_offset_latched][31:24] <= wr_data_latched[31:24];
        if (wr_be_latched[4]) ddr_mem[ddr_offset_latched][39:32] <= wr_data_latched[39:32];
        if (wr_be_latched[5]) ddr_mem[ddr_offset_latched][47:40] <= wr_data_latched[47:40];
        if (wr_be_latched[6]) ddr_mem[ddr_offset_latched][55:48] <= wr_data_latched[55:48];
        if (wr_be_latched[7]) ddr_mem[ddr_offset_latched][63:56] <= wr_data_latched[63:56];
    end
end

// -- DUT ------------------------------------------------------------------
wire pcm_valid, pcm_eof;
reg pcm_ready;
wire signed [15:0] pcm_left, pcm_right;
wire [3:0] error;
wire metadata_valid;
wire [35:0] total_samples;

// Same pseudo-random stall pattern as sim/wav_decoder_tb.sv, for the same
// reason: real backpressure needs to be exercised under stalls, not just
// back-to-back-ready streaming.
reg [4:0] ready_lfsr = 5'h1F;
always @(posedge clk) begin
    ready_lfsr <= {ready_lfsr[3:0], ready_lfsr[4] ^ ready_lfsr[2]};
    pcm_ready <= (ready_lfsr[4:3] != 2'b00);
end

// A permanently-held start (e.g. `!reset`) is wrong, not just sloppy: once
// flac_frame_store's own `active` flag drops (its designed behavior right
// after the end-of-stream token is consumed), a still-asserted start
// immediately re-triggers a full re-init the moment start_ready comes back
// -- corrupting state (total_samples/frame_position reset to 0) right as
// the stream is trying to finish cleanly. One-shot, matching how
// MiSTer_MP3.sv's own real integration gates it (flac_active && !flac_started).
reg dut_started;
always @(posedge clk) begin
    if (reset) dut_started <= 1'b0;
    else dut_started <= 1'b1;
end
wire dut_start = !dut_started;

flac_ddr_decoder #(.ENABLE_RESUME(0), .BASE(BASE)) dut (
    .clk(clk), .reset(reset), .cancel(1'b0), .start(dut_start),
    .resume_frame(1'b0), .resume_sample(36'd0), .resume_total(36'd0),
    .resume_min_block(16'd0), .resume_max_block(16'd0),
    .start_ready(), .quiescent(),
    .input_data(input_data), .input_valid(input_valid), .input_end(input_end), .input_ready(input_ready),
    .metadata_valid(metadata_valid), .total_samples(total_samples),
    .pcm_valid(pcm_valid), .pcm_eof(pcm_eof), .pcm_ready(pcm_ready),
    .pcm_left(pcm_left), .pcm_right(pcm_right), .error(error),
    .mem_addr(mem_addr), .mem_data(mem_data), .mem_be(mem_be),
    .mem_read(mem_read), .mem_write(mem_write), .mem_busy(ddr_busy_r),
    .mem_q(ddr_q_r), .mem_q_valid(ddr_q_valid_r)
);

integer sample_count = 0;
reg saw_eof = 0;
reg saw_error = 0;

always @(posedge clk) begin
    if (!reset && pcm_valid && pcm_ready) begin
        $display("PCM idx=%0d left=%0d right=%0d eof=%0d", sample_count, pcm_left, pcm_right, pcm_eof);
        sample_count <= sample_count + 1;
        if (pcm_eof) saw_eof <= 1;
    end
    // `error` is a level that stays asserted indefinitely once set (the
    // decoder latches into a FAILED state) -- print once, not every cycle
    // for the rest of the run. An earlier version of this testbench printed
    // unconditionally and made a genuine "reject this file" event look like
    // a multi-minute hang purely from log-I/O volume (13M+ lines/minute).
    if (!reset && error != 0 && !saw_error) begin
        $display("ERROR flac_ddr_decoder error=%0d at sample %0d", error, sample_count);
        saw_error <= 1;
    end
end

initial begin
    #12 reset = 0;
end

always @(posedge clk) begin
    if (saw_eof) begin
        $display("RESULT: DONE, %0d samples", sample_count);
        #200 $finish;
    end
    if (saw_error) begin
        #200 $finish;
    end
end

initial begin
    #2000000000 begin
        $display("TIMEOUT after %0d samples, no eof seen", sample_count);
        $finish;
    end
end

endmodule
