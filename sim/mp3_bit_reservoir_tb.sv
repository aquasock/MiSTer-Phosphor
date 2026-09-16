// Streams a real MP3 file through mp3_frame_parser -> mp3_bit_reservoir and,
// on every completed frame, reads back 8 bytes starting at that frame's
// latched frame_read_start pointer -- for comparison against a ground-truth
// concatenated main-data stream built directly from the source file by
// sim/compare_bit_reservoir.py.
`timescale 1ns/1ps
module mp3_bit_reservoir_tb;

parameter HEX_FILE = "";
parameter NUM_FRAMES = 5;
parameter BUF_LOG2 = 11;

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

reg [7:0] mem_in [0:299999];
initial $readmemh(HEX_FILE, mem_in);

integer idx;
wire input_ready;
wire input_valid = 1'b1;
wire [7:0] input_data = mem_in[idx];

always @(posedge clk) begin
    if (reset) idx <= 0;
    else if (input_valid && input_ready) idx <= idx + 1;
end

wire frame_valid, stereo;
wire [1:0] channel_mode, mode_extension;
wire [9:0] frame_len;
wire [8:0] main_data_begin;
wire main_data_valid, main_data_start;
wire [7:0] main_data_byte;

mp3_frame_parser parser (
    .clk(clk), .reset(reset),
    .input_data(input_data), .input_valid(input_valid), .input_ready(input_ready),
    .frame_valid(frame_valid), .stereo(stereo),
    .channel_mode(channel_mode), .mode_extension(mode_extension),
    .frame_len(frame_len), .main_data_begin(main_data_begin),
    .main_data_valid(main_data_valid), .main_data_byte(main_data_byte),
    .main_data_start(main_data_start)
);

reg [BUF_LOG2-1:0] read_addr;
wire [7:0] read_data;

mp3_bit_reservoir #(.BUFFER_BYTES_LOG2(BUF_LOG2)) resv (
    .clk(clk), .reset(reset),
    .main_data_valid(main_data_valid), .main_data_byte(main_data_byte),
    .main_data_start(main_data_start), .main_data_begin(main_data_begin),
    .frame_read_start(),
    .read_addr(read_addr), .read_data(read_data)
);

localparam RD_IDLE=0, RD_SETADDR=1, RD_WAIT=2, RD_CAPTURE=3, RD_DONE=4;
reg [2:0] rd_state = RD_IDLE;
reg [3:0] rd_idx;
reg [BUF_LOG2-1:0] captured_start;
reg [7:0] captured_bytes [0:7];
integer frame_count = 0;

initial begin
    #12 reset = 0;
end

always @(posedge clk) begin
    case (rd_state)
    RD_IDLE: if (frame_valid) begin
        captured_start <= resv.frame_read_start;
        rd_idx <= 0;
        rd_state <= RD_SETADDR;
    end
    RD_SETADDR: begin
        read_addr <= captured_start + rd_idx;
        rd_state <= RD_WAIT;
    end
    RD_WAIT: rd_state <= RD_CAPTURE;
    RD_CAPTURE: begin
        captured_bytes[rd_idx] <= read_data;
        rd_idx <= rd_idx + 1'b1;
        rd_state <= (rd_idx == 7) ? RD_DONE : RD_SETADDR;
    end
    RD_DONE: begin
        frame_count = frame_count + 1;
        $display("FRAME idx=%0d frame_read_start=%0d bytes=%02x %02x %02x %02x %02x %02x %02x %02x",
            frame_count, captured_start, captured_bytes[0], captured_bytes[1], captured_bytes[2],
            captured_bytes[3], captured_bytes[4], captured_bytes[5], captured_bytes[6], captured_bytes[7]);
        rd_state <= RD_IDLE;
        if (frame_count >= NUM_FRAMES) $finish;
    end
    endcase
end

initial begin
    #4000000 begin
        $display("TIMEOUT waiting for %0d frames, got %0d", NUM_FRAMES, frame_count);
        $finish;
    end
end

endmodule
