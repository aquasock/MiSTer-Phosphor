// Streams a real WAV file (converted to a hex byte dump by tools/mp3_to_hex.py,
// which is format-agnostic despite the name) through wav_decoder.sv and dumps
// every PCM sample for comparison against Python's stdlib `wave` module by
// sim/compare_wav_decoder.py.
//
// pcm_ready is toggled on a pseudo-random pattern (not held high always) --
// this module has real backpressure, unlike the from-scratch MP3 pipeline,
// and the one real bug caught while writing it (a registered pcm_eof that
// only updated on the accepting cycle, holding a stale value from the
// previous sample while stalled) would only ever show up under exactly this
// kind of stall pattern, never under back-to-back-ready streaming.
`timescale 1ns/1ps
module wav_decoder_tb;

parameter HEX_FILE = "";

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg [7:0] mem [0:9999999];
initial $readmemh(HEX_FILE, mem);

integer idx = 0;
wire input_ready;
wire input_valid = 1'b1; // no reader-side backpressure to model here; wav_decoder's own input_ready governs consumption
wire [7:0] input_data = mem[idx];

always @(posedge clk) begin
    if (reset) idx <= 0;
    else if (input_valid && input_ready) idx <= idx + 1;
end

wire pcm_valid, pcm_eof;
reg pcm_ready;
wire signed [15:0] pcm_left, pcm_right;

// Simple LFSR-ish pseudo-random ready pattern, deliberately including runs
// of both 0 and 1 so a real multi-cycle stall (not just occasional single-
// cycle gaps) gets exercised.
reg [4:0] ready_lfsr = 5'h1F;
always @(posedge clk) begin
    ready_lfsr <= {ready_lfsr[3:0], ready_lfsr[4] ^ ready_lfsr[2]};
    pcm_ready <= (ready_lfsr[4:3] != 2'b00); // ready ~75% of cycles, in bursts
end

wav_decoder dut (
    .clk(clk), .reset(reset),
    .input_data(input_data), .input_valid(input_valid), .input_ready(input_ready),
    .pcm_valid(pcm_valid), .pcm_eof(pcm_eof), .pcm_ready(pcm_ready),
    .pcm_left(pcm_left), .pcm_right(pcm_right)
);

integer sample_count = 0;
reg saw_eof = 0;

always @(posedge clk) begin
    if (!reset && pcm_valid && pcm_ready) begin
        $display("PCM idx=%0d left=%0d right=%0d eof=%0d", sample_count, pcm_left, pcm_right, pcm_eof);
        sample_count <= sample_count + 1;
        if (pcm_eof) saw_eof <= 1;
    end
end

initial begin
    #12 reset = 0;
end

// Separate block, same reason as every earlier testbench in this project:
// a blocking delay sharing a block with the monitor above would miss any
// PCM events that arrive during it.
always @(posedge clk) begin
    if (saw_eof) begin
        $display("RESULT: DONE, %0d samples", sample_count);
        #200 $finish;
    end
end

initial begin
    #200000000 begin
        $display("TIMEOUT after %0d samples, no eof seen", sample_count);
        $finish;
    end
end

endmodule
