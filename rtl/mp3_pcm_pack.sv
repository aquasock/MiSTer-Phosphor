// Packs mp3_synthesis's per-channel PCM stream into interleaved (L,R) pairs
// for audio_pcm_fifo. mp3_synthesis emits one gci's full 576-sample stream
// (18 time slots x 32 samples) completely before starting the next queued
// one (a single serial FSM -- see mp3_synthesis.sv), so gci=0's stream is
// always fully finished before gci=1 begins, and likewise gci=2 before
// gci=3. That strict ordering is what makes a single (not double-buffered)
// 576-entry buffer sufficient here: channel 0 (gci even) writes into it
// sequentially while gci is even, and channel 1 (gci odd) reads it back
// sequentially -- in the same position order -- while pairing, with no
// possibility of a still-unread position being overwritten early.
//
// stereo/sample_rate are latched once per file (on the first frame_valid
// after a new file starts) rather than forwarded per-value through the
// whole decode pipeline. Real encoders don't change channel mode or
// sample rate mid-file, and retrofitting that forwarding through
// mp3_stereo/mp3_antialias/mp3_imdct/mp3_synthesis (four already-validated
// modules) for a case the accepted profile doesn't need is not worth the
// risk here -- a deliberate simplification specific to this player shell,
// not a change to the decoder core's own per-frame correctness.
module mp3_pcm_pack (
    input wire clk, reset,

    input wire new_file,             // pulses once when a new file starts; re-latches stereo/rate
    input wire frame_valid,          // from mp3_frame_parser
    input wire frame_stereo,
    input wire frame_sample_rate_44k1,

    input wire in_valid,
    input wire [1:0] in_gci,
    input wire signed [15:0] in_data,

    output reg [33:0] fifo_wr_data,  // {rate_48k, stereo, left[16], right[16]}
    output reg fifo_wr_en
);

reg stereo_latched;
reg rate_44k1_latched;
reg latched;

always @(posedge clk) begin
    if (reset || new_file) begin
        latched <= 1'b0;
    end else if (!latched && frame_valid) begin
        stereo_latched     <= frame_stereo;
        rate_44k1_latched  <= frame_sample_rate_44k1;
        latched            <= 1'b1;
    end
end

// Dedicated registered read (the discipline used for every RAM in this
// project since mp3_stereo): the address used to trigger a read at cycle
// T is only available as ch0_rd at cycle T+1, never combinationally
// "immediately." Pairing therefore delays the incoming odd-gci (right
// channel) sample by one cycle via pending_r_sample/pending_pair, so it
// lines up with ch0_rd becoming valid, rather than trying to read and use
// the buffer in the same cycle (which would silently pair against the
// PREVIOUS position, one full sample behind -- the same class of bug
// already found and fixed once in mp3_imdct.sv's ov_addr).
reg signed [15:0] ch0_buf [0:575];
reg [9:0] ch0_wr_pos, ch0_rd_pos;
reg signed [15:0] ch0_rd;
reg signed [15:0] pending_r_sample;
reg pending_pair;

always @(posedge clk) begin
    if (in_valid && !in_gci[0]) ch0_buf[ch0_wr_pos] <= in_data;
    ch0_rd <= ch0_buf[ch0_rd_pos];
end

always @(posedge clk) begin
    fifo_wr_en   <= 1'b0;
    pending_pair <= 1'b0;

    if (reset || new_file) begin
        ch0_wr_pos <= 10'd0;
        ch0_rd_pos <= 10'd0;
    end else begin
        if (in_valid) begin
            if (!in_gci[0]) begin
                // Channel 0 (gci 0 or 2): buffer it. Mono files never see
                // gci 1/3 at all, so also emit immediately here (duplicated
                // to both channels) -- no reason to wait for a pair that
                // will never arrive.
                ch0_wr_pos <= (ch0_wr_pos == 10'd575) ? 10'd0 : ch0_wr_pos + 10'd1;
                if (!stereo_latched) begin
                    fifo_wr_en   <= 1'b1;
                    fifo_wr_data <= {rate_44k1_latched ? 1'b0 : 1'b1, 1'b0, in_data, in_data};
                end
            end else begin
                // Channel 1 (gci 1 or 3): issue the read for this exact
                // position now (ch0_rd_pos hasn't advanced yet this cycle),
                // stash the right sample, and emit the pair next cycle once
                // ch0_rd reflects it.
                ch0_rd_pos       <= (ch0_rd_pos == 10'd575) ? 10'd0 : ch0_rd_pos + 10'd1;
                pending_pair     <= 1'b1;
                pending_r_sample <= in_data;
            end
        end
        if (pending_pair) begin
            fifo_wr_en   <= 1'b1;
            fifo_wr_data <= {rate_44k1_latched ? 1'b0 : 1'b1, 1'b1, ch0_rd, pending_r_sample};
        end
    end
end

endmodule
