// Standalone MiSTer player shell for the from-scratch MP3 decoder built in
// rtl/. Step 9 of the project roadmap (docs/MP3.md) -- minimal on purpose:
// load a file from the OSD's file browser, decode it, play it. No seek, no
// pause, no album/playlist support, no video content beyond the blanked
// signal needed to host the OSD itself (this core has no picture).
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
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_RD,
        DDRAM_DIN, DDRAM_BE, DDRAM_WE} = 0;

assign VGA_SL      = 0;
assign VGA_F1      = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE   = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign OSD_HIDE_MESSAGE = 0;

// Phosphor-specific Menu music-passthrough ports (see module header) --
// this standalone core doesn't participate in that feature.
assign PLAYER_MUSIC = 0;
assign PLAYER_VISUALIZER = 0;
assign PLAYER_MUSIC_PAUSED = 0;
assign PLAYER_PCM_RESET = 0;
assign PLAYER_PCM_VALID = 0;
assign PLAYER_PCM_DATA = 0;
assign PLAYER_UI_CLOCK = clk_sys;
assign PLAYER_UI_STATE = 0;
assign PLAYER_SUBTITLE_COMMAND = 0;

assign LED_USER  = sd_busy;
assign LED_DISK  = 2'b00;
assign LED_POWER = 2'b00;
assign BUTTONS   = 0;

assign VIDEO_ARX = 13'd4;
assign VIDEO_ARY = 13'd3;

///////// Clock / reset /////////
// Cyclone V's dedicated clock-select hardware requires CLK_VIDEO to be
// driven by a PLL output, not a raw input pin -- a real quartus_map error
// on sys_top.v's video clock-switch blocks, not a style choice. Reuses
// MiSTer-Phosphor's own already-working 4-output PLL wrapper (same board/
// chip); only outclk_0 (clk_sys, 20MHz) and outclk_1 (clk_video, 27MHz)
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
	"S0,MP3,Load MP3;",
	"-;",
	"T1,Reset;",
	"R1,Reset and close OSD;",
	"V,v",`BUILD_DATE
};

wire [1:0] buttons;
wire [127:0] status;
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

reg [63:0] file_size_q;
reg reader_start;
always @(posedge clk_sys) begin
	reader_start <= 1'b0;
	if (reset) file_size_q <= 64'd0;
	else if (new_file) begin
		file_size_q  <= img_size;
		reader_start <= 1'b1;
	end
end

wire [8:0] stream_data;
wire stream_valid, stream_ready, reader_idle;
wire sd_busy = !reader_idle;

media_file_reader media_file_reader
(
	.clk(clk_sys), .reset(reset),
	.start(reader_start), .cancel(1'b0), .suspend(1'b0),
	.file_size(file_size_q), .start_offset(64'd0),
	.sd_lba(sd_lba[0]), .sd_blk_cnt(sd_blk_cnt[0]), .sd_rd(sd_rd[0]),
	.sd_ack(sd_ack[0]), .sd_buff_wr(sd_buff_wr),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
	.stream_data(stream_data), .stream_valid(stream_valid), .stream_ready(stream_ready),
	.idle(reader_idle), .byte_position(), .requests(), .completions(), .max_wait(), .error()
);

///////// MP3 decode chain (identical wiring to sim/mp3_synthesis_tb.sv) /////////
wire frame_valid, stereo, sample_rate_44k1;
wire [1:0] channel_mode, mode_extension;
wire [9:0] frame_len;
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
	if (reset) begin
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
wire input_valid = stream_valid && !stream_data[8] && admit_new_frame;
assign stream_ready = stream_data[8] ? 1'b1 : (input_ready && admit_new_frame);

mp3_frame_parser parser
(
	.clk(clk_sys), .reset(reset),
	.input_data(stream_data[7:0]), .input_valid(input_valid), .input_ready(input_ready),
	.frame_valid(frame_valid), .stereo(stereo),
	.channel_mode(channel_mode), .mode_extension(mode_extension),
	.frame_len(frame_len), .main_data_begin(main_data_begin),
	.sample_rate_44k1(sample_rate_44k1),
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
	.clk(clk_sys), .reset(reset),
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
	.clk(clk_sys), .reset(reset),
	.frame_valid(frame_valid), .stereo(stereo), .sample_rate_44k1(sample_rate_44k1),
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
	.clk(clk_sys), .reset(reset),
	.frame_valid(frame_valid), .sample_rate_44k1(sample_rate_44k1),
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
	.clk(clk_sys), .reset(reset),
	.frame_valid(frame_valid), .stereo(stereo), .mode_extension(mode_extension),
	.sample_rate_44k1(sample_rate_44k1),
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
	.clk(clk_sys), .reset(reset),
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
	.clk(clk_sys), .reset(reset),
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
	.clk(clk_sys), .reset(reset),
	.value_valid(imdct_valid), .value_gci(imdct_gci), .value_index(imdct_index), .value_data(imdct_data),
	.out_valid(synth_valid), .out_gci(synth_gci), .out_sample(synth_sample), .out_data(synth_data),
	.idle(synth_idle)
);

///////// PCM pack + clock-domain FIFO + audio-rate output /////////
wire [33:0] pcm_wr_data;
wire pcm_wr_en;

mp3_pcm_pack pcm_pack
(
	.clk(clk_sys), .reset(reset),
	.new_file(new_file),
	.frame_valid(frame_valid), .frame_stereo(stereo), .frame_sample_rate_44k1(sample_rate_44k1),
	.in_valid(synth_valid), .in_gci(synth_gci), .in_data(synth_data),
	.fifo_wr_data(pcm_wr_data), .fifo_wr_en(pcm_wr_en)
);

wire [33:0] pcm_rd_data;
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
	.reset(reset),
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

assign AUDIO_S = 1'b1;
assign AUDIO_MIX = 2'd0;

///////// Minimal blanked video, purely to host the OSD /////////
// This core has no picture of its own; the OSD (needed to select a file
// from the menu in the first place) composites onto whatever video timing
// the core provides, so a valid blanked signal is required even here.
// Straightforward 640x480@~60Hz timing on the PLL's 27MHz clk_video_pll
// output (close enough to standard 25.175MHz -- this core never drives a
// real analog CRT), CE_PIXEL held permanently high (every clk_video_pll
// cycle is a pixel).
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
