// Drives mp3_stereo directly (not through the full pipeline) with a
// synthetic intensity-stereo scenario: real LAME output never sets the
// intensity mode_ext bit (it dropped intensity-stereo encoding entirely),
// so there is no real bitstream to test this path against. The stimulus
// here (channel 0/1 pre-stereo values, channel 1's scale factors,
// mode_extension forced to 3) was captured by patching an instrumented
// FFmpeg build to force this exact scenario through its own real
// compute_stereo() and dumping the inputs and outputs -- see docs/MP3.md.
// sim/compare_stereo_unit.py checks this module's output against
// tools/mp3_stereo_reference.py's compute_stereo_fixed() fed the same
// inputs (that Python function was itself already validated bit-for-bit,
// aside from expected +/-1 ULP rounding, against FFmpeg's real output for
// this same scenario).
`timescale 1ns/1ps
module mp3_stereo_unit_tb;

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg signed [31:0] ch0_mem [0:575];
reg signed [31:0] ch1_mem [0:575];
reg [3:0] sf1_mem [0:21];
initial $readmemh("/tmp/inj_ch0.hex", ch0_mem);
initial $readmemh("/tmp/inj_ch1.hex", ch1_mem);
initial $readmemh("/tmp/inj_sf1.hex", sf1_mem);

reg frame_valid;
reg stereo_r;
reg [1:0] mode_extension_r;
reg [1:0] sr_idx_r;
reg window_switching_flag_r [0:3];
reg [1:0] block_type_r [0:3];
reg mixed_block_flag_r [0:3];

reg sf_valid;
reg [1:0] sf_gci;
reg [5:0] sf_index;
reg [3:0] sf_data;

reg value_valid;
reg [1:0] value_gci;
reg [9:0] value_index;
reg signed [31:0] value_data;

wire out_valid;
wire [1:0] out_gci;
wire [9:0] out_index;
wire signed [31:0] out_data;

mp3_stereo dut (
    .clk(clk), .reset(reset),
    .frame_valid(frame_valid), .stereo(stereo_r), .mode_extension(mode_extension_r),
    .sr_idx(sr_idx_r),
    .window_switching_flag(window_switching_flag_r), .block_type(block_type_r),
    .mixed_block_flag(mixed_block_flag_r),
    .sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
    .value_valid(value_valid), .value_gci(value_gci), .value_index(value_index), .value_data(value_data),
    .out_valid(out_valid), .out_gci(out_gci), .out_index(out_index), .out_data(out_data)
);

integer i;
initial begin
    frame_valid = 0;
    sf_valid = 0; sf_gci = 0; sf_index = 0; sf_data = 0;
    value_valid = 0; value_gci = 0; value_index = 0; value_data = 0;
    stereo_r = 1; mode_extension_r = 2'd3; sr_idx_r = 2'd0;
    for (i = 0; i < 4; i = i + 1) begin
        window_switching_flag_r[i] = 1'b1;
        block_type_r[i] = 2'd1; // "start" block -- window-switched but treated as all-long
        mixed_block_flag_r[i] = 1'b0;
    end

    #12 reset = 0;
    @(negedge clk);
    frame_valid = 1;
    @(negedge clk);
    frame_valid = 0;
    @(negedge clk);

    // Channel 1's scale factors first, matching real decode order (scale
    // factors are read before any Huffman/dequantized value for the same
    // granule/channel).
    for (i = 0; i < 22; i = i + 1) begin
        sf_valid = 1; sf_gci = 2'd1; sf_index = i[5:0]; sf_data = sf1_mem[i];
        @(negedge clk);
    end
    sf_valid = 0;
    @(negedge clk);

    // Channel 0's values, then channel 1's -- matches mp3_dequant's own
    // gci ordering (0 fully streamed before 1 starts).
    for (i = 0; i < 576; i = i + 1) begin
        value_valid = 1; value_gci = 2'd0; value_index = i[9:0]; value_data = ch0_mem[i];
        @(negedge clk);
    end
    for (i = 0; i < 576; i = i + 1) begin
        value_valid = 1; value_gci = 2'd1; value_index = i[9:0]; value_data = ch1_mem[i];
        @(negedge clk);
    end
    value_valid = 0;
    @(negedge clk);

    #200000 begin
        $display("TIMEOUT");
        $finish;
    end
end

always @(posedge clk) begin
    if (out_valid) begin
        $display("ST gci=%0d idx=%0d data=%0d", out_gci, out_index, out_data);
        if (out_index == 10'd575) $display("STDONE gci=%0d", out_gci);
    end
end

integer done_count = 0;
always @(posedge clk) begin
    if (out_valid && out_index == 10'd575) begin
        done_count <= done_count + 1;
        if (done_count + 1 >= 2) #200 $finish;
    end
end

endmodule
