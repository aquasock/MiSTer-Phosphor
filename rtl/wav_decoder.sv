// Standalone-PCM WAV "decoder" -- there is no real decode step, just RIFF
// chunk-walking to find the `data` chunk and stream it through as 16-bit
// stereo sample pairs. Fixed profile, matching every other stage in this
// project: 44.1 kHz/16-bit/stereo. The `fmt ` chunk is parsed explicitly so
// unsupported rates are rejected instead of silently playing at 44.1 kHz.
//
// Byte 0 of the file ("R" of "RIFF") is this module's own byte 0 too --
// MiSTer_MP3.sv's format sniffer buffers the first 4 bytes to decide
// MP3/WAV/FLAC and replays them to whichever decoder wins, so this module
// never needs its own separate sync-acquisition state.
//
// PCM output shape (pcm_valid/pcm_ready/pcm_eof/pcm_left/pcm_right) matches
// rtl/audio/flac/flac_ddr_decoder.sv's own interface deliberately, so both
// feed the same downstream wiring (the native-audio PLAYER_PCM_* rail,
// shared between WAV and FLAC -- see docs/MP3.md) uniformly. Real
// backpressure throughout (pcm_ready, input_ready), not this project's MP3
// pipeline's no-backpressure house style -- appropriate here since this
// module, like FLAC's reused RTL, is not part of that from-scratch pipeline.
module wav_decoder (
    input wire clk, reset,

    input wire [7:0] input_data,
    input wire input_valid,
    output wire input_ready,

    output wire pcm_valid,
    output wire pcm_eof,
    input wire pcm_ready,
    output wire signed [15:0] pcm_left, pcm_right,
    output reg metadata_valid,
    output reg [35:0] total_samples,
    output reg format_valid,
    output reg [31:0] sample_rate,
    output reg format_error
);

localparam
    SKIP_HEADER   = 0,  // 12 bytes: "RIFF" + chunk_size(4) + "WAVE", none of it validated
    CHUNK_ID      = 1,  // 4 bytes: chunk fourCC, MSB-first as read
    CHUNK_SIZE    = 2,  // 4 bytes: chunk size, little-endian
    SKIP_CHUNK    = 3,  // skip a non-`data` chunk's declared byte count (+1 pad byte if odd)
    SAMPLE_LL     = 4,
    SAMPLE_LH     = 5,
    SAMPLE_RL     = 6,
    SAMPLE_RH     = 7,
    EMIT          = 8,
    DONE          = 9,
    VALIDATE_FMT  = 10;

reg [3:0] state;
reg [3:0] byte_idx;          // sub-byte counter within CHUNK_ID/CHUNK_SIZE/SAMPLE_* (0..3)
reg [3:0] header_skip_left;  // counts down from 12 during SKIP_HEADER
reg [31:0] chunk_id;
reg [31:0] chunk_remaining;  // bytes left to skip (SKIP_CHUNK) or stream (data chunk, tracked separately below)
reg [31:0] data_remaining;   // bytes left in the `data` chunk once found
reg chunk_odd;               // this chunk's declared size was odd -- one pad byte follows its data
reg [7:0] sample_ll, sample_lh, sample_rl, sample_rh;
reg [31:0] fmt_size,fmt_rate;
reg [15:0] fmt_tag,fmt_channels,fmt_align,fmt_bits;
reg [5:0] chunk_position;

wire is_data_chunk = (chunk_id == 32'h64617461); // "data"

// Ready in every state that consumes a live input byte this cycle; EMIT
// only consumes the (already-assembled) pcm_ready handshake, not a new
// input byte, so it must not also claim input_ready.
assign input_ready = (state == SKIP_HEADER) || (state == CHUNK_ID) || (state == CHUNK_SIZE) ||
                      (state == SKIP_CHUNK) || (state == SAMPLE_LL) || (state == SAMPLE_LH) ||
                      (state == SAMPLE_RL) || (state == SAMPLE_RH);

// pcm_valid/pcm_eof/pcm_left/pcm_right are all combinational functions of
// already-registered state (state itself, data_remaining, and the four
// sample_* byte registers, all stable throughout EMIT) rather than
// separately registered -- a registered pcm_eof that only updated inside
// `if (pcm_ready)` would hold the PREVIOUS sample's eof value for every
// cycle pcm_valid is asserted but pcm_ready is stalled, since valid and
// eof must be presented together and held stable for the whole handshake,
// not just the accepting cycle.
assign pcm_valid = (state == EMIT);
assign pcm_eof   = (state == EMIT) && (data_remaining == 32'd4);
assign pcm_left  = {sample_lh, sample_ll};
assign pcm_right = {sample_rh, sample_rl};

always @(posedge clk) begin
    if (reset) begin
        state <= SKIP_HEADER;
        header_skip_left <= 4'd12;
        byte_idx <= 4'd0;
        metadata_valid <= 1'b0;
        format_valid <= 1'b0;
        sample_rate <= 32'd0;
        format_error <= 1'b0;
        total_samples <= 36'd0;
        fmt_size<=0;fmt_rate<=0;fmt_tag<=0;fmt_channels<=0;fmt_align<=0;fmt_bits<=0;chunk_position<=0;
    end else begin
        case (state)

        SKIP_HEADER: if (input_valid) begin
            header_skip_left <= header_skip_left - 4'd1;
            if (header_skip_left == 4'd1) begin
                state <= CHUNK_ID;
                byte_idx <= 4'd0;
            end
        end

        CHUNK_ID: if (input_valid) begin
            chunk_id <= {chunk_id[23:0], input_data};
            if (byte_idx == 4'd3) begin
                state <= CHUNK_SIZE;
                byte_idx <= 4'd0;
            end else begin
                byte_idx <= byte_idx + 4'd1;
            end
        end

        // Chunk size is little-endian; assembled directly into byte lanes
        // rather than shifted, since LE byte order is the reverse of the
        // shift-in-MSB-first pattern CHUNK_ID uses for the (literal-order)
        // fourCC.
        CHUNK_SIZE: if (input_valid) begin
            case (byte_idx[1:0])
                2'd0: chunk_remaining[7:0]   <= input_data;
                2'd1: chunk_remaining[15:8]  <= input_data;
                2'd2: chunk_remaining[23:16] <= input_data;
                2'd3: chunk_remaining[31:24] <= input_data;
            endcase
            if (byte_idx == 4'd3) begin
                // Little-endian: input_data is this size field's MOST
                // significant byte, so it takes the top 8 bits here --
                // chunk_remaining[23:0] already holds the other three
                // bytes (least-to-most) from the earlier cycles above.
                chunk_odd <= chunk_remaining[0]; // bit 0 of the full LE value is byte0's LSB, already in chunk_remaining
                if (is_data_chunk) begin
                    data_remaining <= {input_data, chunk_remaining[23:0]};
                    total_samples <= {4'd0,input_data,chunk_remaining[23:2]};
                    metadata_valid <= format_valid;
                    if(!format_valid)begin format_error<=1'b1;state<=DONE;end
                    else state <= ({input_data, chunk_remaining[23:0]} == 32'd0) ? DONE : SAMPLE_LL;
                    byte_idx <= 4'd0;
                end else begin
                    fmt_size<={input_data,chunk_remaining[23:0]};chunk_position<=0;
                    state <= ({input_data, chunk_remaining[23:0]} == 32'd0) ? CHUNK_ID : SKIP_CHUNK;
                end
            end else begin
                byte_idx <= byte_idx + 4'd1;
            end
        end

        SKIP_CHUNK: if (input_valid) begin
            if(chunk_id==32'h666d7420)begin // "fmt "
                case(chunk_position)
                    0:fmt_tag[7:0]<=input_data;1:fmt_tag[15:8]<=input_data;
                    2:fmt_channels[7:0]<=input_data;3:fmt_channels[15:8]<=input_data;
                    4:fmt_rate[7:0]<=input_data;5:fmt_rate[15:8]<=input_data;
                    6:fmt_rate[23:16]<=input_data;7:fmt_rate[31:24]<=input_data;
                    12:fmt_align[7:0]<=input_data;13:fmt_align[15:8]<=input_data;
                    14:fmt_bits[7:0]<=input_data;15:fmt_bits[15:8]<=input_data;
                endcase
                chunk_position<=chunk_position+1'b1;
            end
            if (chunk_remaining == 32'd1) begin
                state <= chunk_id==32'h666d7420 ? VALIDATE_FMT : (chunk_odd ? SKIP_CHUNK : CHUNK_ID);
                chunk_remaining <= chunk_odd ? 32'd1 : 32'd0;
                if(chunk_id!=32'h666d7420)chunk_odd <= 1'b0; // the one pad byte, once consumed, ends the skip
                byte_idx <= 4'd0;
            end else begin
                chunk_remaining <= chunk_remaining - 32'd1;
            end
        end

        VALIDATE_FMT: begin
            sample_rate<=fmt_rate;
            if(fmt_size>=16&&fmt_tag==1&&fmt_channels==2&&fmt_align==4&&fmt_bits==16&&
               (fmt_rate==44100||fmt_rate==48000))begin
                format_valid<=1;format_error<=0;
            end else begin format_valid<=0;format_error<=1;end
            state<=chunk_odd?SKIP_CHUNK:CHUNK_ID;
            chunk_remaining<=chunk_odd?1:0;chunk_odd<=0;byte_idx<=0;
            if(chunk_odd)chunk_id<=0;
        end

        SAMPLE_LL: if (input_valid) begin sample_ll <= input_data; state <= SAMPLE_LH; end
        SAMPLE_LH: if (input_valid) begin sample_lh <= input_data; state <= SAMPLE_RL; end
        SAMPLE_RL: if (input_valid) begin sample_rl <= input_data; state <= SAMPLE_RH; end
        SAMPLE_RH: if (input_valid) begin sample_rh <= input_data; state <= EMIT; end

        EMIT: if (pcm_ready) begin
            data_remaining <= data_remaining - 32'd4;
            state <= (data_remaining == 32'd4) ? DONE : SAMPLE_LL;
            byte_idx <= 4'd0;
        end

        DONE: ; // stay here; nothing more to stream for this file

        default: state <= SKIP_HEADER;
        endcase
    end
end

endmodule
