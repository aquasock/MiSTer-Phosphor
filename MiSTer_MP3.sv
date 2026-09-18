// Standalone MiSTer player shell for the from-scratch MP3 decoder built in
// rtl/. Step 9 of the project roadmap (docs/MP3.md) -- minimal on purpose:
// load a file from the OSD's file browser, decode it, and play it. Embedded
// FLAC CUESHEET albums additionally have pause, seek, track navigation, and
// the Phosphor transport status bar. There is no playlist support or video
// content beyond the raster used by the visualizers and OSD.
//
// Framework: sys/ here is the standard MiSTer core framework (hps_io,
// audio_out, sd_card, the sys_top.v wrapper, board/pin configuration via
// sys.tcl) -- unmodified, copied from the sibling MiSTer-Phosphor project
// (same author, same board, genuinely generic/reusable, not project-
// specific). Three more files are reused the same way, verbatim, because
// they're already-solved, self-contained, non-Phosphor-specific building
// blocks: rtl/media_file_reader.sv (streams a mounted file's bytes via the
// standard hps_io virtual-SD-card protocol), rtl/audio_pcm_fifo.sv (a
// codec-independent async FIFO crossing from clk_sys into the audio
// clock domain), and rtl/audio_pcm_output_adapter.sv (paces FIFO reads at
// exactly 44.1kHz or 48kHz against the fixed 24.576MHz CLK_AUDIO).
// sys/emu_ports.vh still carries a handful of Phosphor-specific
// PLAYER_*/MEDIA_*-prefixed ports (its own Menu music-passthrough
// integration) that this standalone core doesn't participate in -- tied
// off below the same way this file already ties off genuinely-unused
// standard ports like ADC_BUS, rather than risk hand-editing the 2000+
// line sys_top.v to remove them.
//
// No PLL: clk_sys is CLK_50M directly. The whole decode pipeline has
// enormous real-time slack even at 50MHz (every stage's own Quartus fit
// and cycle-budget numbers are documented in docs/MP3.md); timing closure
// work is future scope, not needed to prove the core loads and plays a
// file.
//
// Real-hardware pacing note (the one genuinely new architectural piece
// here, not just wiring): unlike every simulation testbench in sim/,
// which byte-blasts a whole file in and relies on an artificial
// "downstream_idle" gate to avoid overflowing mp3_stereo/mp3_antialias/
// mp3_imdct/mp3_synthesis's queues, a real file read from SD/HPS storage
// has NO inherent real-time pacing either -- the whole file could be read
// in well under a second. So that gate is promoted here from a testbench
// technique into permanent player-shell logic: new frame bytes are only
// admitted into mp3_frame_parser once the previous frame has fully
// drained through every downstream stage (each now exposes a clean
// `idle` port for exactly this, added alongside this player shell rather
// than reached into via hierarchical reference the way the testbenches
// do it).
module emu
(
	`include "sys/emu_ports.vh"
);

///////// Tie off ports this core doesn't use /////////
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
        SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
        SDRAM_nRAS, SDRAM_nCS} = 'Z;
// DDRAM: this project's first real DDR client, for FLAC's frame store
// (flac_frame_store.sv double-buffers full decoded frames there -- too
// large for on-chip block RAM at full profile). Driven for real further
// down, direct passthrough with no arbiter: unlike MiSTer-Phosphor, which
// muxes this same interface between its movie (video) and music (FLAC)
// DDR clients, this core has no video DDR client to mux against.

assign VGA_SL      = 0;
assign VGA_F1      = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE   = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign OSD_HIDE_MESSAGE = 0;

// Phosphor-specific Menu music-passthrough ports -- this standalone core
// doesn't implement the Menu-music/visualizer feature these were built
// for, but PLAYER_MUSIC/PLAYER_PCM_* are also exactly the framework's own
// generic "native audio" rail (sys_top.v wires media_native_audio's
// movie-vs-cd mux to the real output pins already), reused here for
// WAV/FLAC playback -- see the format-dispatch section below and
// docs/MP3.md. Driven for real further down; only the still-genuinely-
// unused ones stay tied off here.
assign PLAYER_SUBTITLE_COMMAND = 0;

assign LED_USER  = sd_busy;
assign LED_DISK  = 2'b00;
assign LED_POWER = 2'b00;
assign BUTTONS   = 0;

// Aspect selection controls HDMI's scaler viewport only. The native core
// raster remains 640x480 in both modes, so direct analog output keeps valid
// 480p timing while Widescreen intentionally stretches that raster to 16:9.
assign VIDEO_ARX = status[121] ? 13'd16 : 13'd4;
assign VIDEO_ARY = status[121] ? 13'd9  : 13'd3;

///////// Clock / reset /////////
// Cyclone V's dedicated clock-select hardware requires CLK_VIDEO to be
// driven by a PLL output, not a raw input pin -- a real quartus_map error
// on sys_top.v's video clock-switch blocks, not a style choice. Reuses
// MiSTer-Phosphor's own already-working 4-output PLL wrapper (same board/
// chip); only outclk_0 (clk_sys, 20MHz) and outclk_1 (clk_video, 25.2MHz)
// are used here. The whole decode pipeline has enormous real-time slack
// even at 20MHz (docs/MP3.md), so the specific rate doesn't matter for
// this MVP; timing closure work is future scope.
wire clk_sys, clk_video_pll;
pll pll
(
	.refclk(CLK_50M), .rst(1'b0),
	.outclk_0(clk_sys), .outclk_1(clk_video_pll),
	.outclk_2(), .outclk_3(), .locked()
);
wire reset = RESET || status[0] || buttons[1];

///////// OSD menu + hps_io /////////
`include "build_id.v"
localparam CONF_STR = {
	"MiSTer_MP3;;",
	// The OSD file-selector's extension field is parsed in fixed 3-character
	// chunks with no delimiters, so a 4-character extension like FLAC can't
	// be listed directly. "FL*" (a `*` as the 3rd character of a chunk)
	// means "match anything starting with these first two letters" on the
	// MiSTer Main/ARM side -- the same trick MiSTer-Phosphor's own CONF_STR
	// already uses ("MPGFL*" = "MPG" + "FL*") for this identical problem.
	"S0,MP3WAVFL*OGG,Load Audio;",
	"O[123:122],Visualizer,Waveforms,FFT,O-Scope;",
	"O[121],Aspect ratio,Standard,Widescreen;",
	"-;",
	"T1,Reset;",
	"R1,Reset and close OSD;",
	"V,v",`BUILD_DATE
};

wire [1:0] buttons;
wire [127:0] status;
assign PLAYER_VISUALIZER = status[123:122];
wire forced_scandoubler;
wire [10:0] ps2_key;

wire [0:0] img_mounted;
wire [63:0] img_size;
wire [31:0] sd_lba[1];
wire [5:0] sd_blk_cnt[1];
wire [0:0] sd_rd, sd_ack;
wire [15:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din[1];
wire sd_buff_wr;
assign sd_buff_din[0] = 16'd0;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1), .VDNUM(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.ps2_key(ps2_key),

	.img_mounted(img_mounted), .img_size(img_size),
	.sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd), .sd_wr(1'b0), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
	.ioctl_wait(1'b0)
);

///////// File reader: streams the mounted file, start to EOF, no seek /////////
reg img_mounted_d;
always @(posedge clk_sys) img_mounted_d <= img_mounted[0];
wire new_file = img_mounted[0] && !img_mounted_d;

// Loading a second file must clear every stage of the decode chain, not
// just mp3_pcm_pack's own latches (its only consumer of new_file before
// this fix). Without this, mp3_frame_parser can still be mid-FSM-state
// from wherever the old file's stream stopped (its own bitrate/sample-rate
// resync logic can eventually recover, but only after decoding garbage for
// a while), mp3_bit_reservoir/mp3_huffman_decoder/mp3_dequant/mp3_stereo/
// mp3_antialias hold stale per-frame data, mp3_imdct's overlap_mem and
// mp3_synthesis's V-history (both deliberately PERSISTENT across frames
// within one file) carry the previous file's tail into the new file's
// first output samples, and the admission-gate registers below could stay
// stuck mid-wait. audio_pcm_fifo can also still hold unplayed samples from
// the old file; dcfifo's aclr is safe to assert from this clock domain.
wire decoder_reset = reset || new_file;

// media_file_reader's IDLE state only ever honors a `start` pulse while
// it's already idle -- a `start` arriving mid-transfer (still reading the
// PREVIOUS file) is silently dropped, and the module just keeps streaming
// the old file's remaining bytes to completion. Switching files while the
// first one is still playing hit exactly this: mp3_decoder_reset correctly
// cleared the decode chain, but the reader itself never stopped, so the old
// file's tail kept flowing in and got audibly re-decoded and played -- the
// user heard the previous file "still going" after selecting a new one.
// Fixed by actually using `cancel` (already built into media_file_reader
// for this, previously tied to 1'b0 and never driven): on a new file,
// assert cancel and wait for the reader to actually report idle (it can't
// abandon an in-flight SD block acknowledgement immediately -- see its own
// header comment -- so this can take a variable number of cycles), then
// drop cancel and pulse start once, exactly as the original single-pulse
// code assumed would always work.
wire album_restart, album_busy, album_resume, album_available, album_seek_available;
wire [40:0] album_offset;
wire [35:0] album_start, album_target, album_total;
wire [15:0] album_min, album_max;
wire album_landed, flac_quiescent;
wire album_track_valid, album_track_changed;
wire [6:0] album_track_number;
wire [35:0] album_track_start, album_track_end;

// Phosphor's transport controls use 360,000 fixed-point ticks per second.
// Keep both the album timeline and the current CUE track timeline available:
// arrows operate on the continuous album position, while F1-F8 use the
// current track duration/origin and the status bar can present track time.
wire [34:0] music_elapsed_q, music_duration_q;
wire [34:0] track_elapsed_q, track_duration_q, track_origin_q;
wire track_times_valid;
wire transport_paused, transport_seeking, transport_restart;
wire [34:0] transport_target_q;
wire album_duration_known;
wire transport_loaded;

reg [63:0] file_size_q, reader_start_offset;
reg reader_start, reader_cancel, switch_pending;
wire flac_restarting = album_restart || (album_busy && (reader_cancel || switch_pending));
always @(posedge clk_sys) begin
	reader_start <= 1'b0;
	if (reset) begin
		file_size_q <= 64'd0;
		reader_start_offset <= 64'd0;
		reader_cancel <= 1'b0;
		switch_pending <= 1'b0;
	end else if (new_file) begin
		file_size_q    <= img_size;
		reader_start_offset <= 64'd0;
		reader_cancel  <= 1'b1;
		switch_pending <= 1'b1;
	end else if (album_restart) begin
		reader_start_offset <= {23'd0, album_offset};
		reader_cancel  <= 1'b1;
		switch_pending <= 1'b1;
	end else if (switch_pending && reader_idle && (!album_busy || flac_quiescent)) begin
		reader_cancel  <= 1'b0;
		reader_start   <= 1'b1;
		switch_pending <= 1'b0;
	end
end

wire [8:0] stream_data;
wire stream_valid, stream_ready, reader_idle;
wire sd_busy = !reader_idle;

media_file_reader media_file_reader
(
	.clk(clk_sys), .reset(reset),
	.start(reader_start), .cancel(reader_cancel), .suspend(1'b0),
	.file_size(file_size_q), .start_offset(reader_start_offset),
	.sd_lba(sd_lba[0]), .sd_blk_cnt(sd_blk_cnt[0]), .sd_rd(sd_rd[0]),
	.sd_ack(sd_ack[0]), .sd_buff_wr(sd_buff_wr),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
	.stream_data(stream_data), .stream_valid(stream_valid), .stream_ready(stream_ready),
	.idle(reader_idle), .byte_position(), .requests(), .completions(), .max_wait(), .error()
);

///////// Format dispatch: sniff the first 4 bytes to pick MP3/WAV/FLAC/Ogg /////////
// Content-sniffed, not extension-based, mirroring MiSTer-Phosphor's own
// media_duration_probe.sv, which tells its FLAC path apart from its movie
// path the same way rather than using separate OSD entries.
//
// The sniffer is the sole consumer of the stream for exactly the first 4
// real (non-EOF) bytes, buffering them; once format_mode is decided, those
// same 4 bytes are replayed to the winning decoder from the buffer (not
// re-read from the file) before live stream bytes resume -- every decoder
// needs to see its own file starting at byte 0 (wav_decoder's RIFF walk
// and flac_stream_decoder's own "fLaC" magic check both included), so the
// sniffed bytes can't simply be discarded.
localparam FMT_MP3 = 2'd0, FMT_WAV = 2'd1, FMT_FLAC = 2'd2, FMT_OGG = 2'd3;
reg [1:0] format_mode;
reg [7:0] sniff_buf [0:3];
reg [2:0] sniff_count;    // 0..4, saturates: real bytes captured so far
reg [2:0] replay_count;   // 0..4, saturates: buffered bytes replayed so far
wire sniffing  = sniff_count < 3'd4;
wire replaying = !sniffing && replay_count < 3'd4;
wire format_committed = !sniffing;

// The active decoder's own input_ready, needed so replay only advances
// once a buffered byte is actually consumed -- see the always block below
// for why this matters (flac_ddr_decoder specifically has a real one-cycle
// gap between its `start` pulse and its internal reset actually
// deasserting, unlike wav_decoder's purely combinational reset).
wire active_input_ready = mp3_active  ? input_ready :
                           wav_active  ? wav_input_ready :
                           flac_active ? flac_input_ready :
                           ogg_active  ? ogg_input_ready :
                           1'b0;

always @(posedge clk_sys) begin
	if (decoder_reset) begin
		sniff_count  <= 3'd0;
		replay_count <= 3'd0;
		format_mode  <= FMT_MP3;
	end else if (sniffing) begin
		if (stream_valid && !stream_data[8]) begin
			sniff_buf[sniff_count[1:0]] <= stream_data[7:0];
			sniff_count <= sniff_count + 3'd1;
			if (sniff_count == 3'd3) begin
				// "RIFF" -> WAV, "fLaC" -> FLAC; anything else defaults to
				// MP3, whose own parser already tolerates leading
				// non-frame bytes (e.g. ID3v2 tags) by design.
				if (sniff_buf[0] == 8'h52 && sniff_buf[1] == 8'h49 &&
				    sniff_buf[2] == 8'h46 && stream_data[7:0] == 8'h46)
					format_mode <= FMT_WAV;
				else if (sniff_buf[0] == 8'h66 && sniff_buf[1] == 8'h4C &&
				         sniff_buf[2] == 8'h61 && stream_data[7:0] == 8'h43)
					format_mode <= FMT_FLAC;
				else if (sniff_buf[0] == 8'h4F && sniff_buf[1] == 8'h67 &&
				         sniff_buf[2] == 8'h67 && stream_data[7:0] == 8'h53)
					format_mode <= FMT_OGG;
				else
					format_mode <= FMT_MP3;
			end
		end
	end else if (replaying) begin
		// A real bug until fixed: this used to advance unconditionally
		// every cycle, not gated by whether the active decoder actually
		// consumed the byte. wav_decoder's reset is a direct combinational
		// function of wav_active, so it was already ready the instant
		// replay began and the bug never showed. flac_ddr_decoder's
		// internal reset instead depends on a registered `decoder_active`
		// flip-flop that only updates the cycle *after* its `start` pulse,
		// so its real input_ready lags flac_active by one cycle -- with
		// the old unconditional advance, the very first replayed byte
		// ('f' of "fLaC") was silently dropped while the decoder was still
		// coming out of reset, corrupting the magic-number check before
		// decode ever really began. Symptom: FLAC files appeared in the
		// browser (sniffing itself doesn't touch the decoder, so format
		// detection worked) but never played.
		if (active_input_ready) replay_count <= replay_count + 3'd1;
	end
end

wire [7:0] decoder_stream_data  = replaying ? sniff_buf[replay_count[1:0]] : stream_data[7:0];
wire       decoder_stream_valid = sniffing  ? 1'b0 :
                                   replaying ? 1'b1 :
                                   (stream_valid && !stream_data[8]);
wire       decoder_stream_eof   = format_committed && !replaying && stream_data[8];

wire mp3_active  = format_committed && (format_mode == FMT_MP3);
wire wav_active  = format_committed && (format_mode == FMT_WAV);
wire flac_active = format_committed && (format_mode == FMT_FLAC);
wire ogg_active  = format_committed && (format_mode == FMT_OGG);

///////// MP3 decode chain (identical wiring to sim/mp3_synthesis_tb.sv) /////////
wire frame_valid, stereo;
wire [1:0] sr_idx;
wire [1:0] channel_mode, mode_extension;
wire [10:0] frame_len;
wire [8:0] main_data_begin;
wire main_data_valid, main_data_start;
wire [7:0] main_data_byte;

wire scfsi_flat [0:1][0:3];
wire [11:0] part2_3_length [0:3];
wire [8:0] big_values [0:3];
wire [7:0] global_gain [0:3];
wire [3:0] scalefac_compress [0:3];
wire window_switching_flag [0:3];
wire [1:0] block_type [0:3];
wire mixed_block_flag [0:3];
wire [4:0] table_select [0:3][0:2];
wire [2:0] subblock_gain [0:3][0:2];
wire [3:0] region0_count [0:3];
wire [2:0] region1_count [0:3];
wire preflag [0:3];
wire scalefac_scale [0:3];
wire count1table_select [0:3];

wire input_ready;

// Real-hardware frame-admission gate -- see module header. Bytes for a
// NEW frame are held off until the previous one has fully drained through
// every downstream stage; bytes for the frame currently being parsed
// continue to flow in regardless (mp3_bit_reservoir already holds more
// than one frame's worth, exactly as every simulation testbench in this
// project already relies on).
//
// Every decode stage being "idle" (finished COMPUTING) is not enough on
// its own: mp3_synthesis computes a whole frame's 1152 PCM samples in a
// tiny fraction of the ~26ms that frame actually takes to PLAY, so
// without also checking the audio FIFO's own occupancy, frames would
// keep getting admitted and decoded far faster than they drain, silently
// overflowing audio_pcm_fifo regardless of how deep it is -- found on
// real hardware as audio garbled from the instant playback started,
// identically on every output path, reproduced deterministically every
// time (see audio_pcm_fifo.sv's header comment for the full writeup).
// pcm_fifo_has_room (declared with the rest of the audio-output wiring
// below) is what actually ties the decode rate to real playback time.
wire stereo_idle, aa_idle, imdct_idle, synth_idle, pcm_fifo_has_room;
wire downstream_idle = stereo_idle && aa_idle && imdct_idle && synth_idle && pcm_fifo_has_room;
reg frame_pending, frame_done_seen;
always @(posedge clk_sys) begin
	if (decoder_reset) begin
		frame_pending <= 1'b0;
		frame_done_seen <= 1'b0;
	end else if (frame_valid) begin
		frame_pending <= 1'b1;
		frame_done_seen <= 1'b0;
	end else if (frame_done) begin
		frame_done_seen <= 1'b1;
	end else if (frame_pending && frame_done_seen && downstream_idle) begin
		frame_pending <= 1'b0;
	end
end
wire admit_new_frame = !frame_pending;
wire input_valid = mp3_active && decoder_stream_valid && admit_new_frame;
wire mp3_stream_ready = decoder_stream_eof ? 1'b1 : (input_ready && admit_new_frame);

mp3_frame_parser parser
(
	.clk(clk_sys), .reset(decoder_reset),
	.input_data(decoder_stream_data), .input_valid(input_valid), .input_ready(input_ready),
	.frame_valid(frame_valid), .stereo(stereo),
	.channel_mode(channel_mode), .mode_extension(mode_extension),
	.frame_len(frame_len), .main_data_begin(main_data_begin),
	.sr_idx(sr_idx),
	.scfsi(scfsi_flat),
	.part2_3_length(part2_3_length), .big_values(big_values), .global_gain(global_gain),
	.scalefac_compress(scalefac_compress), .window_switching_flag(window_switching_flag),
	.block_type(block_type), .mixed_block_flag(mixed_block_flag),
	.table_select(table_select), .subblock_gain(subblock_gain),
	.region0_count(region0_count), .region1_count(region1_count),
	.preflag(preflag), .scalefac_scale(scalefac_scale), .count1table_select(count1table_select),
	.main_data_valid(main_data_valid), .main_data_byte(main_data_byte),
	.main_data_start(main_data_start)
);

wire [10:0] frame_read_start;
wire [10:0] resv_read_addr;
wire [7:0] resv_read_data;

mp3_bit_reservoir resv
(
	.clk(clk_sys), .reset(decoder_reset),
	.main_data_valid(main_data_valid), .main_data_byte(main_data_byte),
	.main_data_start(main_data_start), .main_data_begin(main_data_begin),
	.frame_read_start(frame_read_start),
	.read_addr(resv_read_addr), .read_data(resv_read_data)
);

wire sf_valid;
wire [1:0] sf_gci;
wire [5:0] sf_index;
wire [3:0] sf_data;
wire value_valid;
wire [1:0] value_gci;
wire [9:0] value_index;
wire signed [15:0] value_data;
wire gc_done;
wire [1:0] gc_done_index;
wire frame_done;

mp3_huffman_decoder huff
(
	.clk(clk_sys), .reset(decoder_reset),
	.frame_valid(frame_valid), .stereo(stereo), .sr_idx(sr_idx),
	.scfsi(scfsi_flat),
	.part2_3_length(part2_3_length), .big_values(big_values),
	.scalefac_compress(scalefac_compress), .window_switching_flag(window_switching_flag),
	.block_type(block_type), .mixed_block_flag(mixed_block_flag),
	.table_select(table_select),
	.region0_count(region0_count), .region1_count(region1_count),
	.count1table_select(count1table_select),
	.frame_read_start(frame_read_start),
	.read_addr(resv_read_addr), .read_data(resv_read_data),
	.sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
	.value_valid(value_valid), .value_gci(value_gci), .value_index(value_index), .value_data(value_data),
	.gc_done(gc_done), .gc_done_index(gc_done_index), .frame_done(frame_done)
);

wire dq_valid;
wire [1:0] dq_gci;
wire [9:0] dq_index;
wire signed [31:0] dq_data;

mp3_dequant dequant
(
	.clk(clk_sys), .reset(decoder_reset),
	.frame_valid(frame_valid), .sr_idx(sr_idx),
	.window_switching_flag(window_switching_flag), .block_type(block_type),
	.mixed_block_flag(mixed_block_flag), .global_gain(global_gain),
	.scalefac_scale(scalefac_scale), .preflag(preflag), .subblock_gain(subblock_gain),
	.sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
	.value_valid(value_valid), .value_gci(value_gci), .value_index(value_index), .value_data(value_data),
	.out_valid(dq_valid), .out_gci(dq_gci), .out_index(dq_index), .out_data(dq_data)
);

wire st_valid;
wire [1:0] st_gci;
wire [9:0] st_index;
wire signed [31:0] st_data;
wire st_wsf;
wire [1:0] st_bt;
wire st_mbf;

mp3_stereo stereo_dut
(
	.clk(clk_sys), .reset(decoder_reset),
	.frame_valid(frame_valid), .stereo(stereo), .mode_extension(mode_extension),
	.sr_idx(sr_idx),
	.window_switching_flag(window_switching_flag), .block_type(block_type),
	.mixed_block_flag(mixed_block_flag),
	.sf_valid(sf_valid), .sf_gci(sf_gci), .sf_index(sf_index), .sf_data(sf_data),
	.value_valid(dq_valid), .value_gci(dq_gci), .value_index(dq_index), .value_data(dq_data),
	.out_valid(st_valid), .out_gci(st_gci), .out_index(st_index), .out_data(st_data),
	.out_wsf(st_wsf), .out_bt(st_bt), .out_mbf(st_mbf),
	.idle(stereo_idle)
);

wire aa_valid;
wire [1:0] aa_gci;
wire [9:0] aa_index;
wire signed [31:0] aa_data;
wire aa_wsf;
wire [1:0] aa_bt;
wire aa_mbf;

mp3_antialias aa_dut
(
	.clk(clk_sys), .reset(decoder_reset),
	.value_valid(st_valid), .value_gci(st_gci), .value_index(st_index), .value_data(st_data),
	.value_wsf(st_wsf), .value_bt(st_bt), .value_mbf(st_mbf),
	.out_valid(aa_valid), .out_gci(aa_gci), .out_index(aa_index), .out_data(aa_data),
	.out_wsf(aa_wsf), .out_bt(aa_bt), .out_mbf(aa_mbf),
	.idle(aa_idle)
);

wire imdct_valid;
wire [1:0] imdct_gci;
wire [9:0] imdct_index;
wire signed [31:0] imdct_data;

mp3_imdct imdct_dut
(
	.clk(clk_sys), .reset(decoder_reset),
	.value_valid(aa_valid), .value_gci(aa_gci), .value_index(aa_index), .value_data(aa_data),
	.value_wsf(aa_wsf), .value_bt(aa_bt), .value_mbf(aa_mbf),
	.out_valid(imdct_valid), .out_gci(imdct_gci), .out_index(imdct_index), .out_data(imdct_data),
	.idle(imdct_idle)
);

wire synth_valid;
wire [1:0] synth_gci;
wire [4:0] synth_sample;
wire signed [15:0] synth_data;

mp3_synthesis synth_dut
(
	.clk(clk_sys), .reset(decoder_reset),
	.value_valid(imdct_valid), .value_gci(imdct_gci), .value_index(imdct_index), .value_data(imdct_data),
	.out_valid(synth_valid), .out_gci(synth_gci), .out_sample(synth_sample), .out_data(synth_data),
	.idle(synth_idle)
);

///////// PCM pack + clock-domain FIFO + audio-rate output /////////
wire [34:0] pcm_wr_data;
wire pcm_wr_en;

mp3_pcm_pack pcm_pack
(
	.clk(clk_sys), .reset(reset),
	.new_file(new_file),
	.frame_valid(frame_valid), .frame_stereo(stereo), .frame_sr_idx(sr_idx),
	.in_valid(synth_valid), .in_gci(synth_gci), .in_data(synth_data),
	.fifo_wr_data(pcm_wr_data), .fifo_wr_en(pcm_wr_en)
);

wire [34:0] pcm_rd_data;
wire pcm_fifo_empty, pcm_fifo_full;
wire [10:0] pcm_fifo_wr_usedw;
wire pcm_fifo_rd;

// A full stereo or mono frame is at most 1152 PCM samples (Layer III's
// fixed granule/sample-count); requiring at least that much headroom
// before admitting the next frame is what actually prevents the overflow
// described in audio_pcm_fifo.sv's header comment, regardless of how much
// faster than real-time mp3_synthesis itself computes.
assign pcm_fifo_has_room = pcm_fifo_wr_usedw < 11'd896;

audio_pcm_fifo audio_pcm_fifo
(
	.reset(decoder_reset),
	.wr_clk(clk_sys), .wr_data(pcm_wr_data), .wr_en(pcm_wr_en), .wr_full(pcm_fifo_full), .wr_usedw(pcm_fifo_wr_usedw),
	.rd_clk(CLK_AUDIO), .rd_en(pcm_fifo_rd), .rd_data(pcm_rd_data), .rd_empty(pcm_fifo_empty)
);

wire audio_underrun;

audio_pcm_output_adapter audio_pcm_output_adapter
(
	.clk(CLK_AUDIO), .reset(reset),
	.fifo_data(pcm_rd_data), .fifo_empty(pcm_fifo_empty), .fifo_rd(pcm_fifo_rd),
	.audio_l(AUDIO_L), .audio_r(AUDIO_R), .underrun(audio_underrun)
);

// Observation-only MP3 visualization tap. WAV and FLAC use the native
// audio rail's existing tap; neither path can backpressure playback.
assign PLAYER_CORE_PCM_ACTIVE = mp3_active;
assign PLAYER_CORE_PCM_TICK = pcm_fifo_rd;

assign AUDIO_S = 1'b1;
assign AUDIO_MIX = 2'd0;

///////// WAV + FLAC + Vorbis decoders, sharing the native-audio rail /////////
// This rail is genuinely separate from MP3's own path above, not a
// compromise: media_native_audio (already part of this project's reused
// sys/ framework, previously wired up but left completely inert) is fixed
// at 44.1kHz internally (its own dedicated PLL, SPDIF hardcoded to that
// rate), which is exactly WAV's and FLAC's accepted profile -- while MP3
// already needs 44.1/48/32kHz and has its own working, real-hardware-
// validated multi-rate path above. sys_top.v already wires this project's
// own AUDIO_L/AUDIO_R into media_native_audio's "movie" input and mixes
// movie-vs-cd audio to the real output pins based on PLAYER_MUSIC -- no
// separate output mux needed here, just driving these ports correctly.
wire ogg_input_ready, ogg_pcm_valid, ogg_decoder_ready, ogg_error;
wire signed [31:0] ogg_pcm_left_q31, ogg_pcm_right_q31;
wire [31:0] ogg_sample_rate;
wire ogg_input_valid = ogg_active && decoder_stream_valid;
wire ogg_stream_ready = decoder_stream_eof ? 1'b1 : ogg_input_ready;

vorbis_stream_decoder ogg_decoder
(
	.clk(clk_sys), .reset(decoder_reset || !ogg_active),
	.byte_valid(ogg_input_valid), .byte_data(decoder_stream_data), .byte_ready(ogg_input_ready),
	.pcm_valid(ogg_pcm_valid), .pcm_ready(PLAYER_PCM_READY),
	.pcm_left(ogg_pcm_left_q31), .pcm_right(ogg_pcm_right_q31),
	.sample_rate(ogg_sample_rate), .ready(ogg_decoder_ready), .error(ogg_error)
);

wire wav_input_ready;
wire wav_pcm_valid, wav_pcm_eof;
wire signed [15:0] wav_pcm_left, wav_pcm_right;
wire wav_input_valid = wav_active && decoder_stream_valid;
wire wav_stream_ready = decoder_stream_eof ? 1'b1 : wav_input_ready;

wav_decoder wav_decoder
(
	.clk(clk_sys), .reset(decoder_reset || !wav_active),
	.input_data(decoder_stream_data), .input_valid(wav_input_valid), .input_ready(wav_input_ready),
	.pcm_valid(wav_pcm_valid), .pcm_eof(wav_pcm_eof), .pcm_ready(PLAYER_PCM_READY),
	.pcm_left(wav_pcm_left), .pcm_right(wav_pcm_right)
);

// FLAC: reused verbatim from MiSTer-Phosphor. Its own start/cancel/reset
// split (distinct from wav_decoder's simpler "just hold reset" pattern)
// exists because a DDR request already in flight must drain cleanly rather
// than being abruptly abandoned -- cancel lets flac_frame_store's own state
// machine finish an in-progress mem_read/mem_write before going idle, where
// a hard reset would immediately deassert them mid-transaction. reset
// itself is reserved for a genuinely new file (decoder_reset), matching
// flac_ddr_decoder's own designed lifecycle (its start&&start_ready branch
// already reinitializes every internal counter a fresh session needs).
wire flac_cancel = !flac_active || flac_restarting;
reg flac_started;
always @(posedge clk_sys) begin
	if (decoder_reset || !flac_active || flac_restarting || album_restart) flac_started <= 1'b0;
	else flac_started <= 1'b1;
end
wire flac_start = flac_active && !flac_started && !reader_cancel && !switch_pending;

// flac_ddr_decoder wants a latched "no more bytes are coming" level
// (input_end), not the in-band per-byte EOF marker this project's own
// stream_data[8] convention uses -- latch it the first time it's seen.
reg flac_eof_seen;
always @(posedge clk_sys) begin
	if (decoder_reset || !flac_active || flac_restarting || album_restart) flac_eof_seen <= 1'b0;
	else if (decoder_stream_eof) flac_eof_seen <= 1'b1;
end

wire flac_input_ready;
wire flac_input_valid = flac_active && decoder_stream_valid;
wire flac_stream_ready = decoder_stream_eof ? 1'b1 : flac_input_ready;

wire flac_pcm_valid, flac_pcm_eof;
wire signed [15:0] flac_pcm_left, flac_pcm_right;
wire [3:0] flac_error;
wire [28:0] flac_mem_addr;
wire [63:0] flac_mem_data;
wire [7:0] flac_mem_be;
wire flac_mem_read, flac_mem_write;

flac_ddr_decoder #(.ENABLE_RESUME(1)) flac_decoder
(
	.clk(clk_sys), .reset(decoder_reset), .cancel(flac_cancel), .start(flac_start),
	.resume_frame(album_resume), .resume_sample(album_start), .resume_total(album_total),
	.resume_min_block(album_min), .resume_max_block(album_max),
	.start_ready(), .quiescent(flac_quiescent),
	.input_data(decoder_stream_data), .input_valid(flac_input_valid), .input_end(flac_eof_seen), .input_ready(flac_input_ready),
	.metadata_valid(), .total_samples(),
	.pcm_valid(flac_pcm_valid), .pcm_eof(flac_pcm_eof), .pcm_ready(flac_landing_ready),
	.pcm_left(flac_pcm_left), .pcm_right(flac_pcm_right), .error(flac_error),
	.mem_addr(flac_mem_addr), .mem_data(flac_mem_data), .mem_be(flac_mem_be),
	.mem_read(flac_mem_read), .mem_write(flac_mem_write), .mem_busy(DDRAM_BUSY),
	.mem_q(DDRAM_DOUT), .mem_q_valid(DDRAM_DOUT_READY)
);

assign DDRAM_CLK = clk_sys;
assign DDRAM_ADDR = flac_mem_addr;
assign DDRAM_DIN = flac_mem_data;
assign DDRAM_BE = flac_mem_be;
assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_RD = flac_mem_read;
assign DDRAM_WE = flac_mem_write;

// Landing buffer: needed even without Stage 3's seek UI, since start_sample
// = target_sample = 0 makes it a pure passthrough (discard = cursor <
// target_sample = 0 < 0 = false, always) -- kept in place now so Stage 3
// only has to drive real seek targets into it, not add the module.
wire flac_landing_ready;
wire flac_landing_valid, flac_landing_eof;
wire [31:0] flac_landing_pcm;
reg album_loop_pending = 1'b0;
reg album_loop_restarted = 1'b0;

// A seek restarts the decoder while the native 44.1 kHz sink is already
// clocked and ready.  Releasing an empty FIFO immediately can let the sink
// consume the decoder's first small burst and underrun before the next FLAC
// frame is CRC-admitted from DDR. Hold only the consumer paused while 224
// samples collect in its 256-entry FIFO. Decoding and FIFO writes continue
// while paused, so this adds about 5.1 ms of restart latency without changing
// PCM data and leaves 32 entries of headroom for the clock-domain crossing.
reg flac_prefilling = 1'b1;
reg [7:0] flac_prefill_count = 8'd0;
always @(posedge clk_sys) begin
	if (decoder_reset || !flac_active) begin
		flac_prefilling <= 1'b1;
		flac_prefill_count <= 8'd0;
	end else if (flac_restarting || album_restart) begin
		// A seamless album wrap retains the already-buffered tail and lets it
		// cover decoder restart. Manual navigation resets the FIFO and needs a
		// fresh prefill before the consumer is released.
		flac_prefilling <= !album_loop_pending;
		flac_prefill_count <= 8'd0;
	end else if (flac_prefilling && flac_landing_valid && PLAYER_PCM_READY) begin
		if (flac_landing_eof || flac_prefill_count == 8'd223)
			flac_prefilling <= 1'b0;
		else
			flac_prefill_count <= flac_prefill_count + 1'b1;
	end
end

flac_pcm_landing flac_landing
(
	.clk(clk_sys), .reset(decoder_reset || !flac_active || flac_restarting),
	.start_sample(album_start), .target_sample(album_target),
	.input_valid(flac_pcm_valid), .input_eof(flac_pcm_eof), .input_pcm({flac_pcm_left, flac_pcm_right}), .input_ready(flac_landing_ready),
	.output_valid(flac_landing_valid), .output_eof(flac_landing_eof), .output_pcm(flac_landing_pcm), .output_ready(PLAYER_PCM_READY),
	.landed(album_landed)
);

wire [35:0] native_music_position;
wire native_music_finished, native_music_error;
video_config_cdc #(.WIDTH(38)) album_position_cdc
(
	.src_clk(CLK_AUDIO_CD), .dst_clk(clk_sys),
	.src_data({PLAYER_MUSIC_FINISHED, PLAYER_MUSIC_ERROR, PLAYER_MUSIC_POSITION}),
	.dst_data({native_music_finished, native_music_error, native_music_position})
);
wire [36:0] album_absolute_position = {1'b0, album_target} + {1'b0, native_music_position};
reg [35:0] album_position_bias = 0;
wire [36:0] album_biased_position = album_absolute_position - {1'b0,album_position_bias};
wire [35:0] album_position = album_biased_position[36] ? {36{1'b1}} : album_biased_position[35:0];
// A seamless wrap deliberately does not reset the native PCM sink, so its
// sample counter remains monotonic. Fold each completed album out of the
// displayed/navigation position exactly when the buffered output reaches it.
always @(posedge clk_sys) begin
	if (decoder_reset || (flac_restarting && !album_loop_pending))
		album_position_bias <= 0;
	else if (album_total != 0 && album_biased_position >= {1'b0,album_total})
		album_position_bias <= album_position_bias + album_total;
end

(* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [2:0] album_osd_sync = 0;
always @(posedge clk_sys) album_osd_sync <= {album_osd_sync[1:0], OSD_STATUS};

media_music_time music_time
(
	.clk(clk_sys), .reset(reset || new_file),
	.track_changed(album_track_changed), .track_start(album_track_start),
	.position(album_position), .total(album_total),
	.track_position(album_position >= album_track_start ? album_position - album_track_start : 36'd0),
	.track_total(album_track_end >= album_track_start ? album_track_end - album_track_start : 36'd0),
	.elapsed_q(music_elapsed_q), .total_q(music_duration_q),
	.track_elapsed_q(track_elapsed_q), .track_total_q(track_duration_q),
	.track_start_q(track_origin_q), .track_times_valid(track_times_valid)
);

assign transport_loaded = flac_active && album_available && album_seek_available;

// For an indexed album, consume EOF on the producer side and restart before
// the buffered tail reaches the audio sink. The FIFO is preserved during this
// special restart, allowing track 1 to queue directly behind the final sample.
wire album_source_eof = transport_loaded && flac_landing_valid &&
	flac_landing_eof && PLAYER_PCM_READY;
always @(posedge clk_sys) begin
 if (decoder_reset || !transport_loaded) begin
  album_loop_pending <= 1'b0;
  album_loop_restarted <= 1'b0;
 end else if (album_source_eof && !album_busy && !transport_seeking) begin
  album_loop_pending <= 1'b1;
  album_loop_restarted <= 1'b0;
 end else begin
  // `landed` is still high from the original decode when EOF requests the
  // loop. Do not mistake that stale level for landing at sample zero: wait
  // until the loop restart has actually reset the landing stage and begun.
  if (album_loop_pending && album_restart)
   album_loop_restarted <= 1'b1;
  if (album_loop_pending && album_loop_restarted && album_landed) begin
  album_loop_pending <= 1'b0;
   album_loop_restarted <= 1'b0;
  end
 end
end
wire album_loop_request = album_source_eof && !album_loop_pending &&
	!album_busy && !transport_seeking;
wire album_seek_request = transport_restart || album_loop_request;
wire [34:0] album_seek_target_q = album_loop_request ? 35'd0 : transport_target_q;

media_keyboard_control #(.RESTART_BOTH_DIRECTIONS(1), .ENABLE_SEEK_GATE(1)) transport_keys
(
	.clk(clk_sys), .reset(reset), .new_file(new_file),
	.enabled(transport_loaded), .seek_enabled(album_seek_available && !album_busy),
	.osd_open(album_osd_sync[2]), .key(ps2_key),
	.elapsed_q(music_elapsed_q), .duration_q(track_duration_q),
	.seek_origin_q(track_origin_q),
	.duration_valid(album_track_valid && track_times_valid),
	.seek_done(transport_seeking && album_landed && !album_busy),
	.restart_complete(reader_start),
	.paused(transport_paused), .seek_active(transport_seeking),
	.seek_target_q(transport_target_q), .restart(transport_restart)
);

wire album_ui_visible;
media_album_ui_toggle album_ui_keys
(
	.clk(clk_sys), .reset(reset), .new_file(new_file),
	.enabled(transport_loaded), .osd_open(album_osd_sync[2]),
	.key(ps2_key), .visible(album_ui_visible)
);

assign PLAYER_UI_CLOCK = clk_sys;
media_ui_state #(.CLOCK_HZ(20000000)) player_ui_state
(
	.clk(clk_sys), .reset(reset), .new_file(new_file), .loaded(transport_loaded),
	// N/P and the automatic end-to-start wrap are track transitions, not
	// scrub seeks: both should show album time first and then track time.
	.paused(transport_paused), .seeking(transport_seeking),
	.elapsed_q(music_elapsed_q), .target_q(transport_target_q),
	.duration_q(music_duration_q), .duration_valid(album_total != 0),
	.music_mode(1'b1), .track_changed(album_track_changed),
	.album_ui_visible(album_ui_visible),
	.track_valid(album_track_valid && track_times_valid),
	.track_elapsed_q(track_elapsed_q), .track_duration_q(track_duration_q),
	.track_origin_q(track_origin_q), .album_duration_known(album_duration_known),
	.scene_state(PLAYER_UI_STATE)
);
assign PLAYER_MUSIC_PAUSED = transport_paused || (flac_active && flac_prefilling);

// Navigation temporarily invalidates the cue-table observer while it seeks.
// Keep the last published track on screen until the observer identifies the
// destination; exposing zero makes the renderer fall back to track 1.
reg [6:0] album_ui_track = 0;
always @(posedge clk_sys) begin
	if (reset || new_file || !flac_active)
		album_ui_track <= 0;
	else if (album_track_valid)
		album_ui_track <= album_track_number;
end

flac_album_metadata album_metadata
(
	.write_clk(clk_sys), .reset(reset), .new_file(new_file), .enabled(flac_active),
	.byte_valid(flac_input_valid && flac_input_ready), .byte_data(decoder_stream_data),
	.read_clk(PLAYER_META_CLOCK), .read_address(PLAYER_META_ADDRESS),
	.current_track(album_ui_track),
	.read_data(PLAYER_META_DATA), .valid(PLAYER_META_VALID),
	.artwork_valid(PLAYER_META_ARTWORK_VALID),
	.track_count(PLAYER_META_TRACK_COUNT), .current_title_long(PLAYER_META_TITLE_LONG)
);
assign PLAYER_META_CURRENT_TRACK = album_ui_track;

flac_album_control album_control
(
	.clk(clk_sys), .reset(reset), .new_file(new_file),
	.enabled(flac_active), .osd_open(album_osd_sync[2]), .key(ps2_key),
	.byte_valid(flac_input_valid && flac_input_ready), .byte_data(decoder_stream_data),
	.position(album_position), .file_size(file_size_q),
	.reader_start(reader_start), .landed(album_landed),
	.seek_request(album_seek_request), .seek_target_q(album_seek_target_q),
	.restart(album_restart), .busy(album_busy), .resume_frame(album_resume),
	.start_offset(album_offset), .start_sample(album_start), .target_sample(album_target),
	.total_samples(album_total), .min_block(album_min), .max_block(album_max),
	.tag(), .available(album_available), .seek_available(album_seek_available),
	.current_track_valid(album_track_valid), .track_changed(album_track_changed),
	.current_track_number(album_track_number),
	.current_track_start(album_track_start), .current_track_end(album_track_end)
);

assign stream_ready = sniffing   ? 1'b1 :
                       replaying ? 1'b0 :
                       mp3_active  ? mp3_stream_ready :
                       wav_active  ? wav_stream_ready :
                       flac_active ? flac_stream_ready :
                       ogg_active  ? ogg_stream_ready :
                       1'b0;

assign PLAYER_MUSIC = wav_active || flac_active || ogg_active;
// Held whenever neither WAV nor FLAC is the active format (sniffing/
// replaying/MP3 all included), mirroring MiSTer-Phosphor's own
// `reset_mpeg2 || !media_music_mode` pattern for this same signal -- keeps
// the CD-audio-side FIFO/CDC logic cleanly drained while unused, not just
// reset for one cycle on new_file.
assign PLAYER_PCM_RESET = decoder_reset || (flac_restarting && !album_loop_pending) || !(wav_active || flac_active || ogg_active);
assign PLAYER_PCM_VALID = wav_active ? wav_pcm_valid :
	flac_active ? (flac_landing_valid && !(transport_loaded && flac_landing_eof)) :
	ogg_active ? ogg_pcm_valid : 1'b0;

// The synthesis pipeline output is approximately twice PCM16 amplitude; one
// guard-bit shift places its RMS level within 0.2 dB of the reference decoder.
// Saturate exceptional peaks instead of allowing them to wrap into clicks.
function automatic signed [15:0] ogg_to_pcm16(input signed [31:0] sample);
	reg signed [31:0] scaled;
	begin
		scaled = sample >>> 1;
		if (scaled > 32'sd32767)
			ogg_to_pcm16 = 16'sh7fff;
		else if (scaled < -32'sd32768)
			ogg_to_pcm16 = 16'sh8000;
		else
			ogg_to_pcm16 = scaled[15:0];
	end
endfunction

assign PLAYER_PCM_DATA  = wav_active  ? {wav_pcm_eof, wav_pcm_left, wav_pcm_right} :
                           flac_active ? {flac_landing_eof, flac_landing_pcm} :
                           ogg_active ? {1'b0, ogg_to_pcm16(ogg_pcm_left_q31), ogg_to_pcm16(ogg_pcm_right_q31)} :
                           33'd0;

///////// Minimal blanked video, purely to host the OSD /////////
// This core has no picture of its own; the OSD (needed to select a file
// from the menu in the first place) composites onto whatever video timing
// the core provides, so a valid blanked signal is required even here.
// 640x480 at exactly 60Hz using a 25.2MHz pixel clock and the standard
// 800x525 total raster. Matching HDMI's 60Hz cadence avoids periodic ASCAL
// frame drops, and also provides conventional 480p timing for analog output.
// CE_PIXEL is held high because every clk_video_pll cycle is one pixel.
assign CLK_VIDEO = clk_video_pll;
assign CE_PIXEL = 1'b1;

localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48;
localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33;
localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

reg [9:0] h_cnt;
reg [9:0] v_cnt;
always @(posedge clk_video_pll) begin
	if (reset) begin
		h_cnt <= 0; v_cnt <= 0;
	end else if (CE_PIXEL) begin
		if (h_cnt == H_TOTAL - 1) begin
			h_cnt <= 0;
			v_cnt <= (v_cnt == V_TOTAL - 1) ? 10'd0 : v_cnt + 10'd1;
		end else begin
			h_cnt <= h_cnt + 10'd1;
		end
	end
end

wire h_active = h_cnt < H_ACTIVE;
wire v_active = v_cnt < V_ACTIVE;
assign VGA_HS = ~((h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC));
assign VGA_VS = ~((v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC));
assign VGA_DE = h_active && v_active;
assign VGA_R = 8'd0;
assign VGA_G = 8'd0;
assign VGA_B = 8'd0;

endmodule
