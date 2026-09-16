// MPEG-1 Layer III frame header + side information extraction.
//
// Fixed profile per docs/MP3.md: CBR 128/192 kb/s, 44.1/48 kHz, mono or
// stereo (including joint stereo). No validation of any kind is performed
// on header fields beyond what's structurally required to locate the next
// frame -- input outside the accepted profile is undefined behavior by
// design, not a detected/reported condition.
//
// Frame length is a 4-entry lookup (two bitrates x two sample rates) plus
// the padding bit, not a general multiply/divide -- see docs/MP3.md for
// the derivation. Side-info field widths were derived by requiring the
// granule/channel blocks to sum to exactly the ISO-fixed 256/136 bit total
// (see tools/mp3_header_reference.py), not taken from a single memorized
// source.
module mp3_frame_parser (
    input wire clk, reset,
    input wire [7:0] input_data,
    input wire input_valid,
    output wire input_ready,

    output reg frame_valid,          // one-cycle pulse: side info for this frame is valid on the outputs below
    output reg stereo,                // channel_mode != mono
    output reg [1:0] channel_mode,
    output reg [1:0] mode_extension,
    output reg [9:0] frame_len,       // total frame length in bytes, including the 4-byte header
    output reg [8:0] main_data_begin,
    output reg sample_rate_44k1,      // 1 = 44100 Hz, 0 = 48000 Hz (the only two accepted rates)

    output reg scfsi [0:1][0:3],

    // Flat index gci = granule*2 + channel (0=gr0ch0, 1=gr0ch1, 2=gr1ch0, 3=gr1ch1).
    // For mono, only gci 0 and 2 are meaningful; 1 and 3 hold stale/undefined data.
    output reg [11:0] part2_3_length [0:3],
    output reg [8:0] big_values [0:3],
    output reg [7:0] global_gain [0:3],
    output reg [3:0] scalefac_compress [0:3],
    output reg window_switching_flag [0:3],
    output reg [1:0] block_type [0:3],
    output reg mixed_block_flag [0:3],
    output reg [4:0] table_select [0:3][0:2],
    output reg [2:0] subblock_gain [0:3][0:2],
    output reg [3:0] region0_count [0:3],
    output reg [2:0] region1_count [0:3],
    output reg preflag [0:3],
    output reg scalefac_scale [0:3],
    output reg count1table_select [0:3],

    // Pass-through of the compressed main-data bytes following side info,
    // for a future bit-reservoir stage to tap. Not buffered here.
    output reg main_data_valid,
    output reg [7:0] main_data_byte,

    // Pulses one cycle before this frame's own main_data_valid bytes begin
    // arriving -- the bit-reservoir stage should sample its write pointer
    // on this cycle (before it advances for this frame's bytes) to compute
    // where main_data_begin's backward reach should land.
    output reg main_data_start
);

localparam
    INIT_SYNC=0, COLLECT_HEADER=1, HEADER_DECODE=2, COLLECT_SIDEINFO=3,
    GET_WAIT=4, GET_BIT=5,
    F_MDB=6, F_PRIV=7, F_SCFSI=8,
    F_P23=9, F_BV=10, F_GG=11, F_SC=12, F_WSF=13,
    SW_BT=14, SW_MIXED=15, SW_TS0=16, SW_TS1=17, SW_SBG0=18, SW_SBG1=19, SW_SBG2=20,
    NS_TS0=21, NS_TS1=22, NS_TS2=23, NS_R0=24, NS_R1=25,
    TAIL_PREFLAG=26, TAIL_SCALE=27, TAIL_COUNT1=28,
    GRANULE_NEXT=29,
    MAIN_DATA_SKIP=30, FRAME_DONE=31;

reg [5:0] state, return_state;
reg [7:0] hdr_buf [0:39];
reg [5:0] recv_count;          // bytes collected into hdr_buf so far
reg [5:0] side_info_total_len; // 4 + optional 2 CRC bytes + 32/17 side info bytes
reg [9:0] frame_recv_count;    // bytes consumed since the start of the current frame (header included)

reg protection_bit;
reg [3:0] bitrate_idx;
reg [1:0] sr_idx;
reg padding;

reg [8:0] bit_pos;   // absolute bit offset into hdr_buf, from the start of the frame
reg [11:0] bits_left;
reg [11:0] bits_value;
reg [7:0] byte_q;

reg [2:0] scfsi_cnt;
reg [1:0] nch;
reg gr, ch;
wire [1:0] gci = {gr, ch};

function [9:0] frame_len_lut;
    input [3:0] br_idx;
    input [1:0] s_idx;
    input pad;
    begin case ({br_idx, s_idx})
        {4'd9, 2'd0}:  frame_len_lut = 10'd417 + {9'd0, pad}; // 128k/44100
        {4'd9, 2'd1}:  frame_len_lut = 10'd384 + {9'd0, pad}; // 128k/48000
        {4'd11,2'd0}:  frame_len_lut = 10'd626 + {9'd0, pad}; // 192k/44100
        {4'd11,2'd1}:  frame_len_lut = 10'd576 + {9'd0, pad}; // 192k/48000
        default:       frame_len_lut = 10'd417; // out of profile: undefined behavior, avoid a zero-length livelock
    endcase end
endfunction

// Ready only in the states that actually consume a live stream byte this
// cycle. The bit-parsing states (GET_WAIT/GET_BIT/HEADER_DECODE/FRAME_DONE)
// work entirely from hdr_buf, already fully collected by COLLECT_SIDEINFO --
// asserting ready there would let the upstream source advance past bytes
// this module never actually stores anywhere.
assign input_ready = (state == INIT_SYNC) || (state == COLLECT_HEADER) ||
                      (state == COLLECT_SIDEINFO) || (state == MAIN_DATA_SKIP);

task get_bits;
    input [4:0] n;
    input [5:0] dest;
    begin
        bits_left <= {7'd0, n};
        bits_value <= 0;
        return_state <= dest;
        state <= GET_WAIT;
    end
endtask

integer i, j;
always @(posedge clk) begin
    byte_q <= hdr_buf[bit_pos[8:3]];
    frame_valid <= 0;
    main_data_valid <= 0;
    main_data_start <= 0;

    if (reset) begin
        state <= INIT_SYNC;
        recv_count <= 0;
        frame_recv_count <= 0;
        for (i = 0; i < 4; i = i + 1) begin
            window_switching_flag[i] <= 0;
        end
    end else begin
        case (state)

        INIT_SYNC: if (input_valid) begin
            if (input_data == 8'hFF) begin
                hdr_buf[0] <= input_data;
                recv_count <= 1;
                frame_recv_count <= 1;
                state <= COLLECT_HEADER;
            end
        end

        COLLECT_HEADER: if (input_valid) begin
            hdr_buf[recv_count] <= input_data;
            recv_count <= recv_count + 6'd1;
            frame_recv_count <= frame_recv_count + 10'd1;
            if (recv_count == 3) state <= HEADER_DECODE;
        end

        HEADER_DECODE: begin
            protection_bit <= hdr_buf[1][0];
            bitrate_idx <= hdr_buf[2][7:4];
            sr_idx <= hdr_buf[2][3:2];
            sample_rate_44k1 <= hdr_buf[2][3:2] == 2'd0;
            padding <= hdr_buf[2][1];
            channel_mode <= hdr_buf[3][7:6];
            mode_extension <= hdr_buf[3][5:4];
            stereo <= hdr_buf[3][7:6] != 2'd3;
            nch <= (hdr_buf[3][7:6] == 2'd3) ? 2'd1 : 2'd2;
            frame_len <= frame_len_lut(hdr_buf[2][7:4], hdr_buf[2][3:2], hdr_buf[2][1]);
            side_info_total_len <= 6'd4 + (hdr_buf[1][0] ? 6'd0 : 6'd2) +
                                    ((hdr_buf[3][7:6] == 2'd3) ? 6'd17 : 6'd32);
            state <= COLLECT_SIDEINFO;
        end

        COLLECT_SIDEINFO: if (input_valid) begin
            hdr_buf[recv_count] <= input_data;
            recv_count <= recv_count + 6'd1;
            frame_recv_count <= frame_recv_count + 10'd1;
            if (recv_count + 6'd1 == side_info_total_len) begin
                bit_pos <= {(protection_bit ? 5'd4 : 5'd6), 3'd0};
                gr <= 0; ch <= 0;
                get_bits(5'd9, F_MDB);
            end
        end

        GET_WAIT: state <= GET_BIT;
        GET_BIT: begin
            bits_value <= {bits_value[10:0], byte_q[7 - bit_pos[2:0]]};
            bit_pos <= bit_pos + 9'd1;
            bits_left <= bits_left - 12'd1;
            state <= (bits_left == 1) ? return_state : GET_WAIT;
        end

        F_MDB: begin
            main_data_begin <= bits_value[8:0];
            scfsi_cnt <= 0;
            get_bits(nch == 1 ? 5'd5 : 5'd3, F_PRIV);
        end
        F_PRIV: begin
            // private_bits value itself is never used downstream.
            get_bits(5'd1, F_SCFSI);
        end
        F_SCFSI: begin
            scfsi[scfsi_cnt[2]][scfsi_cnt[1:0]] <= bits_value[0];
            if ((nch == 2'd1 && scfsi_cnt == 3'd3) || (nch == 2'd2 && scfsi_cnt == 3'd7)) begin
                get_bits(5'd12, F_P23);
            end else begin
                scfsi_cnt <= scfsi_cnt + 3'd1;
                get_bits(5'd1, F_SCFSI);
            end
        end

        F_P23: begin part2_3_length[gci] <= bits_value[11:0]; get_bits(5'd9, F_BV); end
        F_BV:  begin big_values[gci] <= bits_value[8:0]; get_bits(5'd8, F_GG); end
        // MS-stereo-only (mode_extension exactly 2'd2, i.e. MS_STEREO bit
        // set and INTENSITY_STEREO bit clear -- combined MS+intensity does
        // NOT get this) folds a 1/sqrt(2) renormalization directly into
        // global_gain here, at parse time, matching FFmpeg's own
        // side-info-parsing-time adjustment (mpegaudiodec_template.c) rather
        // than a separate multiply later: -2 in the exponent's units is
        // exactly 2^(-2/4) = 1/sqrt(2). Every later stage (dequant already
        // written and validated) just consumes global_gain as given, so
        // this is the only place this correction needs to exist.
        F_GG:  begin
            global_gain[gci] <= bits_value[7:0] - (mode_extension == 2'd2 ? 8'd2 : 8'd0);
            get_bits(5'd4, F_SC);
        end
        F_SC:  begin scalefac_compress[gci] <= bits_value[3:0]; get_bits(5'd1, F_WSF); end
        F_WSF: begin
            window_switching_flag[gci] <= bits_value[0];
            if (bits_value[0]) get_bits(5'd2, SW_BT);
            else get_bits(5'd5, NS_TS0);
        end

        SW_BT:    begin block_type[gci] <= bits_value[1:0]; get_bits(5'd1, SW_MIXED); end
        SW_MIXED: begin mixed_block_flag[gci] <= bits_value[0]; get_bits(5'd5, SW_TS0); end
        SW_TS0:   begin table_select[gci][0] <= bits_value[4:0]; get_bits(5'd5, SW_TS1); end
        SW_TS1:   begin table_select[gci][1] <= bits_value[4:0]; get_bits(5'd3, SW_SBG0); end
        SW_SBG0:  begin subblock_gain[gci][0] <= bits_value[2:0]; get_bits(5'd3, SW_SBG1); end
        SW_SBG1:  begin subblock_gain[gci][1] <= bits_value[2:0]; get_bits(5'd3, SW_SBG2); end
        SW_SBG2:  begin subblock_gain[gci][2] <= bits_value[2:0]; get_bits(5'd1, TAIL_PREFLAG); end

        NS_TS0: begin table_select[gci][0] <= bits_value[4:0]; get_bits(5'd5, NS_TS1); end
        NS_TS1: begin table_select[gci][1] <= bits_value[4:0]; get_bits(5'd5, NS_TS2); end
        NS_TS2: begin table_select[gci][2] <= bits_value[4:0]; get_bits(5'd4, NS_R0); end
        NS_R0:  begin region0_count[gci] <= bits_value[3:0]; get_bits(5'd3, NS_R1); end
        NS_R1:  begin region1_count[gci] <= bits_value[2:0]; get_bits(5'd1, TAIL_PREFLAG); end

        TAIL_PREFLAG: begin preflag[gci] <= bits_value[0]; get_bits(5'd1, TAIL_SCALE); end
        TAIL_SCALE:   begin scalefac_scale[gci] <= bits_value[0]; get_bits(5'd1, TAIL_COUNT1); end
        TAIL_COUNT1:  begin count1table_select[gci] <= bits_value[0]; state <= GRANULE_NEXT; end

        GRANULE_NEXT: begin
            if ((nch == 2'd1 && ch == 1'b0) || (nch == 2'd2 && ch == 1'b1)) begin
                ch <= 0;
                if (gr == 1'b1) begin main_data_start <= 1; state <= MAIN_DATA_SKIP; end
                else begin gr <= 1'b1; get_bits(5'd12, F_P23); end
            end else begin
                ch <= ch + 1'b1;
                get_bits(5'd12, F_P23);
            end
        end

        MAIN_DATA_SKIP: if (input_valid) begin
            main_data_valid <= 1;
            main_data_byte <= input_data;
            frame_recv_count <= frame_recv_count + 10'd1;
            if (frame_recv_count + 10'd1 == frame_len) state <= FRAME_DONE;
        end

        FRAME_DONE: begin
            frame_valid <= 1;
            recv_count <= 0;
            frame_recv_count <= 0;
            state <= COLLECT_HEADER;
        end

        default: state <= INIT_SYNC;
        endcase
    end
end

endmodule
