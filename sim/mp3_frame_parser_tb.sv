// Feeds a real MP3 file (converted to a hex byte dump by tools/mp3_to_hex.py)
// through mp3_frame_parser and dumps every decoded field on each frame_valid
// pulse, one line per frame, for comparison against
// tools/mp3_header_reference.py's output by sim/compare_frame_parser.py.
`timescale 1ns/1ps
module mp3_frame_parser_tb;

parameter HEX_FILE = "";
parameter NUM_FRAMES = 5;

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg [7:0] mem [0:299999];
initial $readmemh(HEX_FILE, mem);

integer idx;
wire input_ready;
wire input_valid = 1'b1;
wire [7:0] input_data = mem[idx];

always @(posedge clk) begin
    if (reset) idx <= 0;
    else if (input_valid && input_ready) idx <= idx + 1;
end

wire frame_valid;
wire stereo;
wire [1:0] channel_mode, mode_extension;
wire [9:0] frame_len;
wire [8:0] main_data_begin;

mp3_frame_parser dut (
    .clk(clk), .reset(reset),
    .input_data(input_data), .input_valid(input_valid), .input_ready(input_ready),
    .frame_valid(frame_valid), .stereo(stereo),
    .channel_mode(channel_mode), .mode_extension(mode_extension),
    .frame_len(frame_len), .main_data_begin(main_data_begin)
);

integer frame_count = 0;
integer gci, k;

initial begin
    #12 reset = 0;
end

always @(posedge clk) begin
    if (frame_valid) begin
        frame_count = frame_count + 1;
        $display("FRAME idx=%0d stereo=%0d channel_mode=%0d mode_extension=%0d frame_len=%0d main_data_begin=%0d",
                  frame_count, stereo, channel_mode, mode_extension, frame_len, main_data_begin);
        for (k = 0; k < (stereo ? 8 : 4); k = k + 1)
            $write("  scfsi[%0d][%0d]=%0d", k[2], k[1:0], dut.scfsi[k[2]][k[1:0]]);
        $write("\n");
        for (gci = 0; gci < 4; gci = gci + (stereo ? 1 : 2)) begin
            $display("  gci=%0d part2_3_length=%0d big_values=%0d global_gain=%0d scalefac_compress=%0d window_switching_flag=%0d block_type=%0d mixed_block_flag=%0d table_select0=%0d table_select1=%0d table_select2=%0d subblock_gain0=%0d subblock_gain1=%0d subblock_gain2=%0d region0_count=%0d region1_count=%0d preflag=%0d scalefac_scale=%0d count1table_select=%0d",
                gci, dut.part2_3_length[gci], dut.big_values[gci], dut.global_gain[gci],
                dut.scalefac_compress[gci], dut.window_switching_flag[gci],
                dut.block_type[gci], dut.mixed_block_flag[gci],
                dut.table_select[gci][0], dut.table_select[gci][1], dut.table_select[gci][2],
                dut.subblock_gain[gci][0], dut.subblock_gain[gci][1], dut.subblock_gain[gci][2],
                dut.region0_count[gci], dut.region1_count[gci],
                dut.preflag[gci], dut.scalefac_scale[gci], dut.count1table_select[gci]);
        end
        if (frame_count >= NUM_FRAMES) $finish;
    end
end

initial begin
    #2000000 begin
        $display("TIMEOUT waiting for %0d frames, got %0d", NUM_FRAMES, frame_count);
        $finish;
    end
end

endmodule
