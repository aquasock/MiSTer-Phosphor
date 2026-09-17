// Stereo processing (MS/intensity) and short-block reorder, transcribed
// from FFmpeg's compute_stereo()/reorder_block() (mpegaudiodec_template.c)
// -- see tools/mp3_stereo_reference.py for the derivation and docs/MP3.md
// for the validation methodology (real LAME output never sets the
// intensity-stereo mode_ext bit, so that path is validated against a
// synthetic scenario forced through FFmpeg's own real decoder, not a real
// encoded file).
//
// Architecture: unlike every earlier stage, this one cannot be a simple
// streaming pass. Real intensity-stereo bands are found by scanning HIGH
// frequency to LOW (is channel 1 all-zero there? -- if so it's
// intensity-coded), but mp3_dequant streams values in increasing
// (low-to-high) index order -- backwards from what's needed. Both
// channels of a granule must be fully buffered before any processing can
// start. Reorder (short/mixed blocks only) also needs a whole channel's
// data at once, independent of stereo mode.
//
// Because neither mp3_huffman_decoder nor mp3_dequant has any backpressure
// input, and this module needs many cycles per granule pair to scan
// bands, apply the transform, reorder, and stream the result back out, a
// single buffer risks the next granule pair's incoming values overwriting
// data this module hasn't finished with yet -- the same class of race
// already found once between mp3_frame_parser and mp3_huffman_decoder,
// just at a different pipeline boundary. Fixed here with a genuine
// double-buffer (two full-granule-pair banks): incoming values always
// write into whichever bank isn't currently being processed/streamed, so
// the two operate concurrently instead of racing. This is a real resource
// cost (roughly doubling this module's own buffer RAM), accepted because
// retrofitting a real stall/ready signal through mp3_huffman_decoder's
// existing large, already-validated state machine would risk regressing
// it for a cross-cutting change late in the project.
//
// Scale-factor indexing subtlety worth remembering: short block band 12
// (the highest-frequency short band) has no real transmitted scale factor
// at all -- read_scalefactors pads it with zeros -- so FFmpeg's
// compute_stereo deliberately reuses band 11's scale factor for band 12's
// intensity decisions instead (its "for last band, use previous scale
// factor" comment). Confirmed numerically by hand-tracing FFmpeg's k-index
// arithmetic, not assumed from the comment alone. See sf_index_of() below.
module mp3_stereo (
    input wire clk, reset,

    input wire frame_valid,
    input wire stereo,
    input wire [1:0] mode_extension,
    input wire [1:0] sr_idx,
    input wire window_switching_flag [0:3],
    input wire [1:0] block_type [0:3],
    input wire mixed_block_flag [0:3],

    // Raw scale factors from mp3_huffman_decoder -- only channel 1's are
    // ever used here (intensity positioning always reads the "other"
    // channel's transmitted scale factor).
    input wire sf_valid,
    input wire [1:0] sf_gci,
    input wire [5:0] sf_index,
    input wire [3:0] sf_data,

    // Dequantized spectral values from mp3_dequant.
    input wire value_valid,
    input wire [1:0] value_gci,
    input wire [9:0] value_index,
    input wire signed [31:0] value_data,

    // Same 576-per-granule/channel cadence as every earlier stage, but not
    // in real time relative to the input -- this module runs many cycles
    // behind while it buffers, processes and reorders a whole granule pair.
    output reg out_valid,
    output reg [1:0] out_gci,
    output reg [9:0] out_index,
    output reg signed [31:0] out_data,

    // The window_switching_flag/block_type/mixed_block_flag for the gci
    // out_gci CURRENTLY refers to -- travels alongside the value stream
    // rather than making a downstream consumer re-derive it from the
    // shared per-frame arrays. Necessary because this module's own output
    // can lag frame_valid by many frames' worth of processing time (a
    // full buffer+scan+reorder+stream cycle per granule pair), unlike
    // mp3_dequant's bounded few-cycle pipeline lag -- a downstream stage
    // reading window_switching_flag[out_gci] fresh from mp3_frame_parser
    // could easily be looking at a NEWER frame's value than the one
    // out_gci/out_data actually describe. Found the hard way: the next
    // stage (mp3_antialias) originally did exactly that and silently
    // misclassified a pure-short block as needing antialiasing once its
    // input lagged far enough behind frame_valid -- see docs/MP3.md.
    output reg out_wsf,
    output reg [1:0] out_bt,
    output reg out_mbf,

    // True when this module has nothing in progress and nothing queued --
    // used by the top-level player to gate how fast the file reader may
    // feed new frames on real hardware, where (unlike a live broadcast
    // stream) nothing else naturally paces byte arrival to real playback
    // time. See mp3_synthesis_tb.sv's header comment for the identical
    // gating logic this mirrors, now promoted from a testbench-only
    // technique to a real, permanent part of the player shell.
    output wire idle
);

reg l_stereo;
reg [1:0] l_mode_extension;
reg [1:0] l_sr_idx;
reg l_window_switching_flag [0:3];
reg [1:0] l_block_type [0:3];
reg l_mixed_block_flag [0:3];

integer li;
always @(posedge clk) begin
    if (frame_valid) begin
        l_stereo <= stereo;
        l_mode_extension <= mode_extension;
        l_sr_idx <= sr_idx;
        for (li = 0; li < 4; li = li + 1) begin
            l_window_switching_flag[li] <= window_switching_flag[li];
            l_block_type[li] <= block_type[li];
            l_mixed_block_flag[li] <= mixed_block_flag[li];
        end
    end
end

function [5:0] long_end_of;
    input [1:0] bt; input mbf; input wsf;
    begin
        if (wsf && bt == 2'd2) long_end_of = mbf ? 6'd8 : 6'd0;
        else long_end_of = 6'd22;
    end
endfunction
function [5:0] short_start_of;
    input [1:0] bt; input mbf; input wsf;
    begin
        if (wsf && bt == 2'd2) short_start_of = mbf ? 6'd3 : 6'd0;
        else short_start_of = 6'd13;
    end
endfunction
// long_end only ever takes 3 values for our profile (0/8/22), and the
// first-8-long-bands sample count happens to be exactly 36 at both
// supported sample rates -- see docs/MP3.md -- so this is a plain lookup,
// not a running accumulation.
function [9:0] long_samples_of;
    input [5:0] long_end_f;
    begin
        if (long_end_f == 6'd22) long_samples_of = 10'd576;
        else if (long_end_f == 6'd8) long_samples_of = 10'd36;
        else long_samples_of = 10'd0;
    end
endfunction

// -- Band-size ROMs (same content as mp3_dequant's, reloaded here since
// this module doesn't share dequant's instance) --------------------------
reg [7:0] band_size_long_rom [0:65];
reg [7:0] band_size_short_rom [0:38];
initial $readmemh("rtl/mp3_dequant_band_size_long.hex", band_size_long_rom);
initial $readmemh("rtl/mp3_dequant_band_size_short.hex", band_size_short_rom);
// long_row widened to 7 bits (not 6) on purpose: long_row+band_i_f is a
// self-determined expression (used directly as a ROM index) with no wider
// co-operand to force extension, and row 2's max address (44+21=65)
// overflows 6 bits -- would have silently wrapped to 1 for every high-band
// long lookup at 32kHz.
wire [6:0] long_row = (l_sr_idx == 2'd0) ? 7'd0 : (l_sr_idx == 2'd1) ? 7'd22 : 7'd44;
wire [5:0] short_row = (l_sr_idx == 2'd0) ? 6'd0 : (l_sr_idx == 2'd1) ? 6'd13 : 6'd26;

function [7:0] band_size_of;
    input is_long_f;
    input [5:0] band_i_f;
    begin
        if (is_long_f) band_size_of = band_size_long_rom[long_row + band_i_f];
        else band_size_of = band_size_short_rom[short_row + band_i_f];
    end
endfunction

// Flat scale-factor index for channel 1's raw scale factor at (is_long,
// band_i, window_w) -- matches mp3_huffman_decoder's sf_index numbering
// exactly (long bands 0..long_end-1, then short bands short_start..12 with
// window innermost), computed directly rather than by replicating
// FFmpeg's iterative k-decrement scheme. See module header for the band-12
// special case.
function [5:0] sf_index_of;
    input is_long_f;
    input [5:0] band_i_f;
    input [1:0] window_w_f;
    input [5:0] long_end_f;
    input [5:0] short_start_f;
    reg [5:0] eff_band;
    begin
        if (is_long_f) begin
            sf_index_of = (band_i_f == 6'd21) ? 6'd20 : band_i_f;
        end else begin
            eff_band = (band_i_f == 6'd12) ? 6'd11 : band_i_f;
            sf_index_of = long_end_f + (eff_band - short_start_f) * 6'd3 + {4'd0, window_w_f};
        end
    end
endfunction

// -- Intensity-position table + 1/sqrt(2), Q0.20 fixed point (derived
// directly from is_table[k] = tan(k*pi/12)/(1+tan(k*pi/12)) and its
// complement, not copied from FFmpeg's own differently-scaled internal
// constants -- see tools/mp3_stereo_reference.py) ------------------------
localparam IS_FRAC_BITS = 20;
localparam signed [21:0] ISQRT2_FIXED = 22'sd741455;
function signed [21:0] is_table0;
    input [3:0] sf;
    begin
        case (sf)
            4'd0: is_table0 = 22'sd0;
            4'd1: is_table0 = 22'sd221590;
            4'd2: is_table0 = 22'sd383805;
            4'd3: is_table0 = 22'sd524288;
            4'd4: is_table0 = 22'sd664771;
            4'd5: is_table0 = 22'sd826986;
            default: is_table0 = 22'sd1048576;
        endcase
    end
endfunction
function signed [21:0] is_table1;
    input [3:0] sf;
    begin
        case (sf)
            4'd0: is_table1 = 22'sd1048576;
            4'd1: is_table1 = 22'sd826986;
            4'd2: is_table1 = 22'sd664771;
            4'd3: is_table1 = 22'sd524288;
            4'd4: is_table1 = 22'sd383805;
            4'd5: is_table1 = 22'sd221590;
            default: is_table1 = 22'sd0;
        endcase
    end
endfunction

// -- Double-buffered granule-pair storage --------------------------------
// Each logical buffer is two PHYSICALLY SEPARATE per-bank arrays, not one
// array with a runtime bank index, and each physical array is driven by
// exactly one always block. This matters: an earlier version used a single
// `buf0[0:1][0:575]` array with two separate always blocks touching it --
// one for the continuous wr_bank-indexed buffering write, one for the
// FSM's own proc_bank-indexed read/write. Quartus's RAM inference refused
// to infer that as block RAM at all ("uninferred due to unsupported
// read-during-write behavior" -- it cannot statically prove wr_bank and
// proc_bank never coincide, even though they never do by construction),
// falling back to ~98,000 logic cells of individual registers for a module
// that should cost a few hundred ALMs. Splitting each bank into its own
// array, with a single unified always block per array selecting between
// "buffering write" and "FSM access" by which role this array currently
// holds (always mutually exclusive, since wr_bank != proc_bank always),
// gives Quartus a single well-defined write per array per cycle insteadof
// an ambiguous multi-process pattern.
reg signed [31:0] buf0_a [0:575], buf0_b [0:575];
reg signed [31:0] buf1_a [0:575], buf1_b [0:575];
reg [3:0] sf1_a [0:38], sf1_b [0:38];
reg signed [31:0] scratch [0:255];

reg wr_bank;

// Unified buf0/buf1/sf1 addressing for every FSM-side access. A first
// version of this module read/wrote these arrays with a different literal
// address expression inline in each state (MS, apply, reorder-out,
// reorder-in, stream...); consolidating every access behind one address
// bus (matching the read/ROM pattern already used everywhere else in this
// project) is necessary groundwork for the per-bank split above, though
// on its own it did not fix the inference issue -- see the module
// header's note; the real fix is the physical bank split.
reg [9:0] fsm_addr;
reg fsm_wr_en0, fsm_wr_en1;
reg signed [31:0] fsm_wr_data0, fsm_wr_data1;
wire signed [63:0] apply_prod0 = (apply_mode == APPLY_MS) ? (fsm_rd0 + fsm_rd1) * ISQRT2_FIXED : fsm_rd0 * is_v0;
wire signed [63:0] apply_prod1 = (apply_mode == APPLY_MS) ? (fsm_rd0 - fsm_rd1) * ISQRT2_FIXED : fsm_rd0 * is_v1;
always @* begin
    fsm_addr = 10'd0;
    fsm_wr_en0 = 1'b0; fsm_wr_en1 = 1'b0;
    fsm_wr_data0 = 32'sd0; fsm_wr_data1 = 32'sd0;
    case (state)
        S_MS_READ: fsm_addr = scan_pos;
        S_MS_WRITE: begin
            fsm_addr = scan_pos;
            fsm_wr_en0 = 1'b1; fsm_wr_en1 = 1'b1;
            fsm_wr_data0 = fsm_rd0 + fsm_rd1;
            fsm_wr_data1 = fsm_rd0 - fsm_rd1;
        end
        S_SCAN_CHECK_READ: fsm_addr = scan_pos + {2'd0, check_j};
        S_APPLY_READ: if (!(apply_mode == APPLY_MS && !ms_enabled)) fsm_addr = scan_pos + {2'd0, apply_j};
        S_APPLY_WRITE: begin
            fsm_addr = scan_pos + {2'd0, apply_j};
            fsm_wr_en0 = 1'b1; fsm_wr_en1 = 1'b1;
            fsm_wr_data0 = round_shift21(apply_prod0);
            fsm_wr_data1 = round_shift21(apply_prod1);
        end
        S_REORDER_OUT_READ: fsm_addr = reorder_out_addr;
        S_REORDER_IN_WRITE: begin
            fsm_addr = reorder_in_addr;
            fsm_wr_en0 = !reorder_ch; fsm_wr_en1 = reorder_ch;
            fsm_wr_data0 = rd0; fsm_wr_data1 = rd0; // rd0 holds scratch[reorder_copy_idx] here, set by S_REORDER_IN_READ
        end
        S_STREAM_READ: fsm_addr = stream_pos;
        default: ;
    endcase
end

// Each physical bank array gets its OWN dedicated registered read output,
// with the "which bank does the FSM want" selection applied AFTERWARD as
// a plain combinational mux -- not folded into the same register as the
// memory read. A first attempt read both banks into one ternary feeding a
// single register (`fsm_rd0 <= sel ? buf0_a[addr] : buf0_b[addr]`); Quartus
// refused to infer block RAM for either array ("uninferred due to
// asynchronous read logic"), because from each array's own perspective its
// output no longer feeds a register directly -- it feeds a mux. Registering
// each array's read unconditionally, then muxing the two registered values,
// is the pattern Quartus's inference actually recognizes.
reg signed [31:0] buf0_a_rd, buf0_b_rd;
reg signed [31:0] buf1_a_rd, buf1_b_rd;
reg [3:0] sf1_a_rd, sf1_b_rd;
wire signed [31:0] fsm_rd0 = (proc_bank == 1'b0) ? buf0_a_rd : buf0_b_rd;
wire signed [31:0] fsm_rd1 = (proc_bank == 1'b0) ? buf1_a_rd : buf1_b_rd;
wire [3:0] sf1_rd = (proc_bank == 1'b0) ? sf1_a_rd : sf1_b_rd;

// Writes accept a new value every cycle unconditionally, same reasoning as
// mp3_dequant's own pipeline: mp3_huffman_decoder's value stream can
// arrive back-to-back indefinitely.
//
// The read/write role of each physical bank array must be decided from
// wr_bank and proc_bank INDEPENDENTLY, not by assuming proc_bank is always
// the complement of wr_bank. An earlier version made that assumption (a
// natural-looking simplification: only two banks exist, so surely one is
// always "the other one" from the second) and it is wrong whenever the
// 2-deep pending-pair queue actually holds two entries at once: wr_bank
// can toggle twice (parking back on its original value) while proc_bank
// is still catching up to the FIRST queued pair, so wr_bank and proc_bank
// can transiently hold the SAME value even though they refer to different
// pending pairs. Found via comparison against tools/mp3_stereo_reference.py
// showing a single dropped (zeroed) value out of 69,120 checked -- rare
// because it only manifests when both queue slots are genuinely occupied
// at once.
always @(posedge clk) begin
    if (wr_bank == 1'b0) begin
        if (value_valid && !value_gci[0]) buf0_a[value_index] <= value_data;
    end else if (proc_bank == 1'b0) begin
        if (fsm_wr_en0) buf0_a[fsm_addr] <= fsm_wr_data0;
    end
    buf0_a_rd <= buf0_a[fsm_addr];

    if (wr_bank == 1'b1) begin
        if (value_valid && !value_gci[0]) buf0_b[value_index] <= value_data;
    end else if (proc_bank == 1'b1) begin
        if (fsm_wr_en0) buf0_b[fsm_addr] <= fsm_wr_data0;
    end
    buf0_b_rd <= buf0_b[fsm_addr];
end

always @(posedge clk) begin
    if (wr_bank == 1'b0) begin
        if (value_valid && value_gci[0]) buf1_a[value_index] <= value_data;
    end else if (proc_bank == 1'b0) begin
        if (fsm_wr_en1) buf1_a[fsm_addr] <= fsm_wr_data1;
    end
    buf1_a_rd <= buf1_a[fsm_addr];

    if (wr_bank == 1'b1) begin
        if (value_valid && value_gci[0]) buf1_b[value_index] <= value_data;
    end else if (proc_bank == 1'b1) begin
        if (fsm_wr_en1) buf1_b[fsm_addr] <= fsm_wr_data1;
    end
    buf1_b_rd <= buf1_b[fsm_addr];
end

always @(posedge clk) begin
    if (wr_bank == 1'b0) begin
        if (sf_valid && sf_gci[0]) sf1_a[sf_index] <= sf_data;
    end
    sf1_a_rd <= sf1_a[cur_sf_index];

    if (wr_bank == 1'b1) begin
        if (sf_valid && sf_gci[0]) sf1_b[sf_index] <= sf_data;
    end
    sf1_b_rd <= sf1_b[cur_sf_index];
end

wire trigger = value_valid && value_index == 10'd575 && (l_stereo ? value_gci[0] : 1'b1);

// A completed granule pair's side-info (window_switching_flag/block_type/
// mixed_block_flag for both of its gci's) is snapshotted into the queue
// entry at push time, not re-read from l_* later: mp3_huffman_decoder can
// finish decoding BOTH granules of a frame -- and therefore fire this
// module's trigger twice -- well before this module's own processing of
// even the FIRST pair has gotten past its 576-cycle stream-out phase
// (measured directly: as few as ~300 cycles between two triggers of a
// simple mono frame, against ~1150+ cycles needed just to stream one
// pair back out). A single proc_bank/active_gci register pair silently
// clobbered mid-flight here -- found via comparison against
// tools/mp3_stereo_reference.py showing every value one full granule pair
// behind where it should be. Because both granules of one frame can
// legitimately queue up before draining even starts (their data is
// already fully resident by the time frame_valid fires, so no amount of
// upstream byte-arrival pacing can prevent it -- this is not a testbench
// artifact), and because the l_* side-info arrays get overwritten by the
// very next frame_valid, snapshotting into a real 2-deep queue (matching
// the two data banks) is required for correctness, not just double
// buffering the data itself.
reg q_bank [0:1];
reg [1:0] q_gci0 [0:1];
reg [1:0] q_gci1 [0:1];
reg q_wsf0 [0:1]; reg [1:0] q_bt0 [0:1]; reg q_mbf0 [0:1];
reg q_wsf1 [0:1]; reg [1:0] q_bt1 [0:1]; reg q_mbf1 [0:1];
reg q_stereo [0:1];
reg [1:0] q_mode_extension [0:1];
reg [1:0] q_count;
reg q_head, q_tail;

reg proc_bank;
reg [1:0] active_gci0, active_gci1;
reg active_wsf0, active_wsf1;
reg [1:0] active_bt0, active_bt1;
reg active_mbf0, active_mbf1;
reg active_stereo;
reg [1:0] active_mode_extension;

// -- Main processing FSM --------------------------------------------------
localparam
    S_WAIT_TRIGGER    = 0,
    S_MS_READ         = 1, S_MS_WRITE          = 2,
    S_SCAN_INIT       = 3,
    S_SCAN_SIZE       = 4,
    S_SCAN_CHECK_READ = 5, S_SCAN_CHECK_EVAL   = 6,
    S_SCAN_SF_READ    = 7, S_SCAN_SF_EVAL      = 8,
    S_APPLY_READ      = 9, S_APPLY_WRITE       = 10,
    S_SCAN_NEXT       = 11,
    S_REORDER_CH_INIT   = 12,
    S_REORDER_BAND_SIZE = 13,
    S_REORDER_OUT_READ  = 14, S_REORDER_OUT_WRITE = 15,
    S_REORDER_IN_READ   = 16, S_REORDER_IN_WRITE  = 17,
    S_REORDER_BAND_NEXT = 18,
    S_REORDER_CH_NEXT   = 19,
    S_STREAM_READ     = 20, S_STREAM_EMIT       = 21,
    S_STREAM_CH_NEXT  = 22;

reg [4:0] state;
assign idle = (state == 5'd0) && (q_count == 2'd0);

// Stereo-scan working registers.
reg is_long;              // 0 = scanning short bands, 1 = scanning long bands
reg [5:0] band_i;
reg [1:0] window_w;
reg [9:0] scan_pos;       // running frequency position, counts DOWN as bands are consumed
reg [7:0] scan_len;
reg [7:0] check_j, apply_j;
reg nz_found_short [0:2];
reg nz_found_long;
reg [5:0] scan_long_end, scan_short_start;
reg ms_enabled;
reg apply_mode;           // 0 = MS/passthrough, 1 = intensity reconstruction
localparam APPLY_MS = 1'b0, APPLY_INTENSITY = 1'b1;
reg signed [21:0] is_v0, is_v1;
reg signed [31:0] rd0, rd1;

// Reorder working registers.
reg reorder_ch;             // 0 or 1
reg [1:0] reorder_gci;
reg [5:0] reorder_band_i;
reg [9:0] reorder_ptr;
reg [7:0] reorder_f;
reg [1:0] reorder_w;
reg [7:0] reorder_len;
reg [8:0] reorder_total;    // 3 * reorder_len
reg [8:0] reorder_copy_idx;

// Stream-out working registers.
reg stream_ch;
reg [9:0] stream_pos;

function signed [31:0] round_shift21;
    input signed [63:0] product;
    begin
        if (product >= 0)
            round_shift21 = (product + (64'sd1 <<< (IS_FRAC_BITS - 1))) >>> IS_FRAC_BITS;
        else
            round_shift21 = -((-product + (64'sd1 <<< (IS_FRAC_BITS - 1))) >>> IS_FRAC_BITS);
    end
endfunction

wire [5:0] cur_sf_index = sf_index_of(is_long, band_i, window_w, scan_long_end, scan_short_start);
wire [9:0] reorder_out_addr = reorder_ptr + {2'd0, reorder_w} * {2'd0, reorder_len} + {2'd0, reorder_f};
wire [8:0] reorder_scratch_addr = {1'b0, reorder_f} * 9'd3 + {7'd0, reorder_w};
wire [9:0] reorder_in_addr = reorder_ptr + {1'b0, reorder_copy_idx};

wire pop_now = (state == S_WAIT_TRIGGER) && (q_count != 2'd0);

always @(posedge clk) begin
    out_valid <= 0;

    if (reset) begin
        state <= S_WAIT_TRIGGER;
        wr_bank <= 0;
        q_count <= 0; q_head <= 0; q_tail <= 0;
    end else begin
        // -- Queue push: a newly completed granule pair enters the queue.
        // Combined with the pop logic below in one always block (rather
        // than a separate one keyed only on `trigger`) so a push and a pop
        // landing on the same cycle can't race on q_count via two
        // different blocks each reading its stale pre-edge value.
        if (trigger) begin
            q_bank[q_tail] <= wr_bank;
            q_gci0[q_tail] <= l_stereo ? {value_gci[1], 1'b0} : value_gci;
            q_gci1[q_tail] <= value_gci;
            q_wsf0[q_tail] <= l_window_switching_flag[l_stereo ? {value_gci[1], 1'b0} : value_gci];
            q_bt0[q_tail]  <= l_block_type[l_stereo ? {value_gci[1], 1'b0} : value_gci];
            q_mbf0[q_tail] <= l_mixed_block_flag[l_stereo ? {value_gci[1], 1'b0} : value_gci];
            q_wsf1[q_tail] <= l_window_switching_flag[value_gci];
            q_bt1[q_tail]  <= l_block_type[value_gci];
            q_mbf1[q_tail] <= l_mixed_block_flag[value_gci];
            q_stereo[q_tail] <= l_stereo;
            q_mode_extension[q_tail] <= l_mode_extension;
            q_tail <= ~q_tail;
            wr_bank <= ~wr_bank;
        end
        q_count <= q_count + (trigger ? 2'd1 : 2'd0) - (pop_now ? 2'd1 : 2'd0);
        if (pop_now) q_head <= ~q_head;

        case (state)

        S_WAIT_TRIGGER: if (pop_now) begin
            proc_bank <= q_bank[q_head];
            active_gci0 <= q_gci0[q_head];
            active_gci1 <= q_gci1[q_head];
            active_wsf0 <= q_wsf0[q_head]; active_bt0 <= q_bt0[q_head]; active_mbf0 <= q_mbf0[q_head];
            active_wsf1 <= q_wsf1[q_head]; active_bt1 <= q_bt1[q_head]; active_mbf1 <= q_mbf1[q_head];
            active_stereo <= q_stereo[q_head];
            active_mode_extension <= q_mode_extension[q_head];
            if (q_stereo[q_head] && q_mode_extension[q_head] != 2'd0) begin
                if (q_mode_extension[q_head] == 2'd2) begin
                    scan_pos <= 0;
                    state <= S_MS_READ;
                end else begin
                    state <= S_SCAN_INIT;
                end
            end else begin
                reorder_ch <= 0;
                state <= S_REORDER_CH_INIT;
            end
        end

        // -- MS-only fast path: unconditional full-576 butterfly ----------
        // (buf0/buf1 read/write for this state is handled by the unified
        // fsm_addr/fsm_rd*/fsm_wr* logic below -- see its header comment.)
        S_MS_READ: begin
            state <= S_MS_WRITE;
        end
        S_MS_WRITE: begin
            if (scan_pos == 10'd575) begin
                reorder_ch <= 0;
                state <= S_REORDER_CH_INIT;
            end else begin
                scan_pos <= scan_pos + 10'd1;
                state <= S_MS_READ;
            end
        end

        // -- Banded MS/intensity scan (mode_extension 1 or 3) -------------
        S_SCAN_INIT: begin : scan_init_blk
            reg [5:0] le, ss;
            le = long_end_of(active_bt1, active_mbf1, active_wsf1);
            ss = short_start_of(active_bt1, active_mbf1, active_wsf1);
            scan_long_end <= le;
            scan_short_start <= ss;
            ms_enabled <= active_mode_extension[1];
            nz_found_short[0] <= 1'b0; nz_found_short[1] <= 1'b0; nz_found_short[2] <= 1'b0;
            check_j <= 0; apply_j <= 0;
            scan_pos <= 10'd576;
            if (ss < 6'd13) begin
                is_long <= 1'b0;
                band_i <= 6'd12;
                window_w <= 2'd2;
            end else begin
                is_long <= 1'b1;
                band_i <= le - 6'd1;
                nz_found_long <= 1'b0;
            end
            state <= S_SCAN_SIZE;
        end

        S_SCAN_SIZE: begin
            scan_len <= band_size_of(is_long, band_i);
            scan_pos <= scan_pos - {2'd0, band_size_of(is_long, band_i)};
            apply_mode <= APPLY_MS;
            if ((!is_long && nz_found_short[window_w]) || (is_long && nz_found_long))
                state <= S_APPLY_READ;
            else
                state <= S_SCAN_CHECK_READ;
        end

        S_SCAN_CHECK_READ: begin
            state <= S_SCAN_CHECK_EVAL;
        end
        S_SCAN_CHECK_EVAL: begin
            if (fsm_rd1 != 0) begin
                if (!is_long) nz_found_short[window_w] <= 1'b1;
                else nz_found_long <= 1'b1;
                apply_mode <= APPLY_MS;
                state <= S_APPLY_READ;
            end else if (check_j == scan_len - 8'd1) begin
                check_j <= 0;
                state <= S_SCAN_SF_READ;
            end else begin
                check_j <= check_j + 8'd1;
                state <= S_SCAN_CHECK_READ;
            end
        end

        S_SCAN_SF_READ: begin
            // sf1_rd already reflects sf1_[a|b][cur_sf_index] here: it's
            // registered every cycle from cur_sf_index (see the sf1 always
            // block above), and band_i/window_w (which cur_sf_index derives
            // from) have been stable since this band's scan began. This
            // state just gives it one more cycle before S_SCAN_SF_EVAL
            // reads it, for clarity/symmetry with the other read states.
            state <= S_SCAN_SF_EVAL;
        end
        S_SCAN_SF_EVAL: begin
            if (sf1_rd >= 4'd7) begin
                apply_mode <= APPLY_MS;
            end else begin
                apply_mode <= APPLY_INTENSITY;
                is_v0 <= is_table0(sf1_rd);
                is_v1 <= is_table1(sf1_rd);
            end
            state <= S_APPLY_READ;
        end

        S_APPLY_READ: begin
            if (apply_mode == APPLY_MS && !ms_enabled) begin
                // Real, independently-coded band with MS not enabled at
                // all (intensity-only mode): leave both channels exactly
                // as decoded, no read/modify/write needed.
                state <= S_SCAN_NEXT;
            end else begin
                state <= S_APPLY_WRITE;
            end
        end
        S_APPLY_WRITE: begin
            if (apply_j == scan_len - 8'd1) begin
                apply_j <= 0;
                state <= S_SCAN_NEXT;
            end else begin
                apply_j <= apply_j + 8'd1;
                state <= S_APPLY_READ;
            end
        end

        S_SCAN_NEXT: begin
            check_j <= 0;
            apply_j <= 0;
            if (!is_long) begin
                if (window_w == 2'd0) begin
                    if (band_i == scan_short_start) begin
                        // Short region exhausted -- move to the long
                        // region if it exists, else the stereo phase is
                        // done for this granule pair.
                        if (scan_long_end > 6'd0) begin
                            is_long <= 1'b1;
                            band_i <= scan_long_end - 6'd1;
                            nz_found_long <= nz_found_short[0] | nz_found_short[1] | nz_found_short[2];
                            state <= S_SCAN_SIZE;
                        end else begin
                            reorder_ch <= 0;
                            state <= S_REORDER_CH_INIT;
                        end
                    end else begin
                        band_i <= band_i - 6'd1;
                        window_w <= 2'd2;
                        state <= S_SCAN_SIZE;
                    end
                end else begin
                    window_w <= window_w - 2'd1;
                    state <= S_SCAN_SIZE;
                end
            end else begin
                if (band_i == 6'd0) begin
                    reorder_ch <= 0;
                    state <= S_REORDER_CH_INIT;
                end else begin
                    band_i <= band_i - 6'd1;
                    state <= S_SCAN_SIZE;
                end
            end
        end

        // -- Per-channel reorder (short/mixed blocks only) ----------------
        S_REORDER_CH_INIT: begin : reorder_ch_init_blk
            reg [1:0] gci;
            reg [5:0] le;
            reg wsf; reg [1:0] bt; reg mbf;
            gci = reorder_ch ? active_gci1 : active_gci0;
            wsf = reorder_ch ? active_wsf1 : active_wsf0;
            bt  = reorder_ch ? active_bt1  : active_bt0;
            mbf = reorder_ch ? active_mbf1 : active_mbf0;
            reorder_gci <= gci;
            if (wsf && bt == 2'd2) begin
                le = long_end_of(bt, mbf, wsf);
                reorder_band_i <= short_start_of(bt, mbf, wsf);
                reorder_ptr <= long_samples_of(le);
                state <= S_REORDER_BAND_SIZE;
            end else begin
                state <= S_REORDER_CH_NEXT;
            end
        end

        S_REORDER_BAND_SIZE: begin
            reorder_len <= band_size_of(1'b0, reorder_band_i);
            reorder_total <= band_size_of(1'b0, reorder_band_i) * 9'd3;
            reorder_f <= 0;
            reorder_w <= 0;
            if (reorder_band_i > 6'd12) state <= S_REORDER_CH_NEXT;
            else state <= S_REORDER_OUT_READ;
        end

        S_REORDER_OUT_READ: begin
            state <= S_REORDER_OUT_WRITE;
        end
        S_REORDER_OUT_WRITE: begin
            scratch[reorder_scratch_addr] <= reorder_ch ? fsm_rd1 : fsm_rd0;
            if (reorder_w == 2'd2) begin
                reorder_w <= 0;
                if (reorder_f == reorder_len - 8'd1) begin
                    reorder_copy_idx <= 0;
                    state <= S_REORDER_IN_READ;
                end else begin
                    reorder_f <= reorder_f + 8'd1;
                    state <= S_REORDER_OUT_READ;
                end
            end else begin
                reorder_w <= reorder_w + 2'd1;
                state <= S_REORDER_OUT_READ;
            end
        end

        S_REORDER_IN_READ: begin
            rd0 <= scratch[reorder_copy_idx];
            state <= S_REORDER_IN_WRITE;
        end
        S_REORDER_IN_WRITE: begin
            if (reorder_copy_idx == reorder_total - 9'd1) begin
                state <= S_REORDER_BAND_NEXT;
            end else begin
                reorder_copy_idx <= reorder_copy_idx + 9'd1;
                state <= S_REORDER_IN_READ;
            end
        end

        S_REORDER_BAND_NEXT: begin
            reorder_ptr <= reorder_ptr + {1'b0, reorder_total};
            reorder_band_i <= reorder_band_i + 6'd1;
            state <= S_REORDER_BAND_SIZE;
        end

        S_REORDER_CH_NEXT: begin
            if (!reorder_ch && active_stereo) begin
                reorder_ch <= 1;
                state <= S_REORDER_CH_INIT;
            end else begin
                stream_ch <= 0;
                stream_pos <= 0;
                state <= S_STREAM_READ;
            end
        end

        // -- Stream the finished granule pair out, channel 0 then 1 -------
        S_STREAM_READ: begin
            state <= S_STREAM_EMIT;
        end
        S_STREAM_EMIT: begin
            out_valid <= 1;
            out_gci <= stream_ch ? active_gci1 : active_gci0;
            out_index <= stream_pos;
            out_data <= stream_ch ? fsm_rd1 : fsm_rd0;
            out_wsf <= stream_ch ? active_wsf1 : active_wsf0;
            out_bt  <= stream_ch ? active_bt1  : active_bt0;
            out_mbf <= stream_ch ? active_mbf1 : active_mbf0;
            if (stream_pos == 10'd575) begin
                state <= S_STREAM_CH_NEXT;
            end else begin
                stream_pos <= stream_pos + 10'd1;
                state <= S_STREAM_READ;
            end
        end
        S_STREAM_CH_NEXT: begin
            if (!stream_ch && active_stereo) begin
                stream_ch <= 1;
                stream_pos <= 0;
                state <= S_STREAM_READ;
            end else begin
                state <= S_WAIT_TRIGGER;
            end
        end

        default: state <= S_WAIT_TRIGGER;
        endcase
    end
end

endmodule
