// Bit-reservoir ring buffer for MPEG-1 Layer III main data.
//
// main_data_begin (from mp3_frame_parser) says how many bytes before the
// current frame's own main-data bytes the frame's actual granule/Huffman
// data starts -- up to 511 bytes backward, borrowing unused capacity from
// previous frames. This is required even under this project's fixed-CBR
// profile: per-granule bit allocation still varies frame to frame at a
// fixed nominal bitrate, which is the entire reason the reservoir exists
// (see docs/MP3.md).
//
// BUFFER_BYTES_LOG2=11 (2048 bytes) comfortably covers the worst case: 511
// bytes of backward reach plus one frame's own main-data contribution
// (up to ~591 bytes at 192 kb/s/44.1 kHz), with margin for the Huffman
// consumer lagging slightly behind the incoming stream.
module mp3_bit_reservoir #(parameter BUFFER_BYTES_LOG2 = 11) (
    input wire clk, reset,

    // From mp3_frame_parser.
    input wire main_data_valid,
    input wire [7:0] main_data_byte,
    input wire main_data_start,
    input wire [8:0] main_data_begin,

    // Latched write-pointer-minus-main_data_begin for whichever frame most
    // recently pulsed main_data_start -- this is where that frame's own
    // granule/Huffman decode should begin reading once its main_data_valid
    // bytes have finished arriving (i.e. by the time frame_valid pulses).
    output reg [BUFFER_BYTES_LOG2-1:0] frame_read_start,

    // Byte-read port for the (future) Huffman/bit-unpacking stage, and for
    // direct verification in simulation. One cycle of read latency.
    input wire [BUFFER_BYTES_LOG2-1:0] read_addr,
    output reg [7:0] read_data
);

localparam BUFFER_BYTES = (1 << BUFFER_BYTES_LOG2);

reg [7:0] mem [0:BUFFER_BYTES-1];
reg [BUFFER_BYTES_LOG2-1:0] write_pointer;

always @(posedge clk) begin
    if (reset) begin
        write_pointer <= 0;
        frame_read_start <= 0;
    end else begin
        if (main_data_start)
            frame_read_start <= write_pointer - main_data_begin;
        if (main_data_valid) begin
            mem[write_pointer] <= main_data_byte;
            write_pointer <= write_pointer + 1'b1;
        end
    end
    read_data <= mem[read_addr];
end

endmodule
