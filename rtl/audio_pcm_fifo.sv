// Entry 395: codec-independent PCM clock-domain FIFO.
// Word layout: {rate_48k, stereo, left[15:0], right[15:0]}.
//
// Depth widened from the original 256 to 2048, and wr_usedw exposed, for
// this project's own use: MP3's Layer III frame produces 1152 PCM
// samples, and mp3_synthesis emits that entire frame's worth in a tiny
// fraction of the ~26ms it takes to actually PLAY at 44.1/48kHz (the same
// enormous real-time slack every stage in this pipeline has, documented
// throughout docs/MP3.md). Found on real hardware: audio was garbled from
// the instant playback started, identically on every output path
// (analog/S/PDIF/HDMI, ruling out anything downstream of this FIFO), and
// reproduced deterministically every time -- exactly the signature of a
// fixed, structural overflow rather than a timing race. The original
// 256-entry depth alone was the proximate cause, but widening it is not
// sufficient by itself: this codebase's established house style has NO
// backpressure anywhere (mp3_synthesis can't be told to pause), and the
// player shell's own frame-admission gate only waits for the decode
// pipeline to finish COMPUTING a frame, not for that frame's audio to
// have actually been PLAYED (which still takes the full ~26ms regardless
// of how fast it was computed) -- so frames would keep piling up
// indefinitely into any fixed-size FIFO, just taking longer to first
// overflow. `wr_usedw` lets the player shell gate new-frame admission on
// this FIFO having genuine room for a full frame, which is what actually
// ties the decode rate to real playback time; the 2048 depth is comfortable
// margin on top of that, not the fix by itself.
module audio_pcm_fifo
(
    input  wire        reset,

    input  wire        wr_clk,
    input  wire [33:0] wr_data,
    input  wire        wr_en,
    output wire        wr_full,
    output wire [10:0] wr_usedw,   // for the player shell's real-time admission pacing -- see header comment

    input  wire        rd_clk,
    input  wire        rd_en,
    output wire [33:0] rd_data,
    output wire        rd_empty
);

dcfifo #(
    .lpm_numwords         (2048),
    .lpm_showahead        ("ON"),
    .lpm_type             ("dcfifo"),
    .lpm_width            (34),
    .lpm_widthu           (11),
    .overflow_checking    ("ON"),
    .underflow_checking   ("ON"),
    .use_eab              ("ON"),
    .rdsync_delaypipe     (4),
    .wrsync_delaypipe     (4),
    .write_aclr_synch     ("ON"),
    .read_aclr_synch      ("ON")
) pcm_fifo
(
    .aclr    (reset),

    .data    (wr_data),
    .wrclk   (wr_clk),
    .wrreq   (wr_en),
    .wrfull  (wr_full),
    .wrusedw (wr_usedw),

    .q       (rd_data),
    .rdclk   (rd_clk),
    .rdreq   (rd_en),
    .rdempty (rd_empty)
);

endmodule
