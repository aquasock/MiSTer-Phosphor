// IMDCT + windowing + overlap-add + frequency inversion, for both long
// blocks and the short-block path (three 12-point IMDCTs per subband,
// combined via a 6-sample-shifted overlap-add into the same 36-wide
// shape a long block's own IMDCT produces, for block_type==2's short
// portion). See tools/mp3_imdct_reference.py for the derivation
// (implemented from the direct ISO 11172-3 mathematical definition, not
// FFmpeg's specific fast factorization algorithm, then hand-traced
// against FFmpeg's actual fused imdct12()+overlap-add implementation to
// derive the short-block combination structure) and docs/MP3.md for the
// validation writeup.
//
// The short-block path needs NO separate datapath: at most 2 of the 3
// short windows ever contribute to a given output position, so
// tools/mp3_imdct_rom_gen.py precomputes a 4th 36x18 combined-coefficient
// table (bt_sel index 3) with the inactive window's taps simply zero, and
// the exact same 18-tap MAC loop below (S_MAC_ISSUE/S_MAC_ACC) that
// computes a long block's 36-tap-style sum also computes a short-block
// output position correctly, adding nothing for the zeroed taps.
//
// Architecture: like mp3_stereo/mp3_antialias, buffers a whole 576-value
// channel before processing (each subband's IMDCT needs all 18 of its
// input values at once), and uses the same double-buffer + 2-deep
// pending-channel queue to absorb mp3_antialias's own multi-cycle-per-
// value output pace -- see mp3_stereo.sv's header comment for the full
// architectural rationale, repeated at every stage since (each one's own
// processing time exceeds its input's production rate).
//
// A NEW kind of state for this project: the overlap-add carry (18 values
// per channel per subband = 2*32*18 = 1152 values) is the first state
// that persists ACROSS FRAMES, not just within one buffered channel or
// granule pair -- reset only on module reset, never touched by
// frame_valid or by the per-channel double-buffer swap.
//
// Also new: the transform's OUTPUT is a genuine transpose of its INPUT
// (input is subband-major: position sb*18+k; output is time-major:
// position t*32+sb), so it cannot be computed in place over the input
// buffer the way every earlier stage's position-preserving transforms
// could -- a third 576-entry buffer holds the transposed result until
// streaming.
//
// window[block_type][i] * cos(...) is folded into one precomputed ROM
// (tools/mp3_imdct_rom_gen.py) so the accumulation loop computes the
// windowed IMDCT output directly, with no separate windowing pass or its
// own extra rounding step.
module mp3_imdct (
    input wire clk, reset,

    input wire value_valid,
    input wire [1:0] value_gci,
    input wire [9:0] value_index,
    input wire signed [31:0] value_data,
    input wire value_wsf,
    input wire [1:0] value_bt,
    input wire value_mbf,

    // Time-major, subband-minor: out_index = t*32 + sb (t=0..17, sb=0..31),
    // matching the layout the polyphase synthesis filterbank (not yet
    // built) needs.
    output reg out_valid,
    output reg [1:0] out_gci,
    output reg [9:0] out_index,
    output reg signed [31:0] out_data
);

// -- Combined IMDCT+window coefficient ROM -------------------------------
// Flat index bt_sel*648 + i*18 + k, where bt_sel 0/1/2 -> block_type
// 0(long)/1(start)/3(stop), bt_sel 3 -> the short-block combined table
// (see module header comment and tools/mp3_imdct_rom_gen.py), i=0..35,
// k=0..17.
reg signed [17:0] coeff_rom [0:2591];
initial $readmemh("rtl/mp3_imdct_coeff.hex", coeff_rom);

// Gated on wsf first, same convention as mp3_dequant.sv/mp3_stereo.sv's
// long_end_of()/short_start_of(): block_type/mixed_block_flag are only
// ever WRITTEN by mp3_frame_parser when window_switching_flag=1 -- for a
// normal (non-window-switched) block they hold whatever they last held,
// which for the very first such granule in a stream is X (never written
// at all). Reading bt directly without gating on wsf first let that X
// propagate all the way through this ROM address and poison every output
// value of the first granule processed -- found via simulation showing
// every value of the first channel come out undefined even after fixing
// the (real, but not the only) overlap_mem initialization bug.
function [1:0] bt_sel_of;
    input wsf;
    input [1:0] bt;
    begin
        bt_sel_of = (wsf && bt == 2'd1) ? 2'd1 : ((wsf && bt == 2'd3) ? 2'd2 : 2'd0);
    end
endfunction

localparam FRAC_BITS = 16;
function signed [31:0] round_shift16;
    input signed [63:0] acc;
    begin
        if (acc >= 0)
            round_shift16 = (acc + (64'sd1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS;
        else
            round_shift16 = -((-acc + (64'sd1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS);
    end
endfunction

// -- 4-way-buffered per-channel INPUT storage, 4-deep pending queue ------
// Every earlier stage (mp3_stereo.sv/mp3_antialias.sv) gets away with only
// 2-deep buffering because THEIR own processing is fast enough relative
// to their input's production rate that at most one extra channel can
// ever pile up behind the one being processed. That assumption breaks
// here: this module's own per-channel processing (~44,000 cycles, the
// 32-subband x 36-tap x 18-k MAC loop) is dramatically slower than
// upstream's, and a single STEREO frame completes FOUR channels (2
// granules x 2 channels) in the time this module drains just one. With
// only 2 queue slots / 2 physical buffers, the 3rd and 4th channel of a
// stereo frame would arrive before the queue ever drains once: the 3rd
// trigger overwrites the still-unpopped queue entry left by the 1st (its
// data silently gone -- the "MISSING channel" bug), and the 4th trigger's
// incoming value_valid writes land in the same physical buffer bank still
// being re-read every cycle by the in-progress MAC loop, corrupting a few
// of its samples mid-read (the "value mismatch" bug) rather than losing
// the channel outright. Found via simulation: mono (2 channels/frame)
// passed bit-exact every time; stereo (4 channels/frame) failed with
// exactly these two symptoms. 4 is the true worst case for this profile
// (2 granules x max 2 channels), not a margin-of-safety guess -- a NEW
// frame's channels can't start arriving until the current frame's finish
// draining through this module in real operation (bit-rate-limited input
// pacing gives ~26ms/frame vs. ~3.5ms to drain 4 channels), so in-flight
// channels never span a frame boundary.
reg signed [31:0] buf_a [0:575], buf_b [0:575], buf_c [0:575], buf_d [0:575];
reg [1:0] wr_bank;
reg [1:0] proc_bank;

reg [1:0] q_bank [0:3];
reg [1:0] q_gci [0:3];
reg q_wsf [0:3]; reg [1:0] q_bt [0:3]; reg q_mbf [0:3];
reg [2:0] q_count;
reg [1:0] q_head, q_tail;

reg [1:0] active_gci;
reg [1:0] active_bt_sel;      // pre-selected here (bt_sel_of), not the raw block_type
reg [5:0] active_long_end;    // 2 for mixed, 0 for pure short, 32 for a non-short block
reg active_is_short;          // window_switching_flag && block_type==2

// -- Third buffer: transposed (time-major) output for this channel ------
reg signed [31:0] out_buf [0:575];

// -- Persistent overlap-add state: 2 channels x 32 subbands x 18 values,
// reset only on module reset. Single flat array, single unified process
// (one address bus, one write port, a dedicated registered read -- the
// same RAM-inference discipline used everywhere in this project since the
// mp3_stereo bug). Address = channel*576 + sb*18 + pos.
reg signed [31:0] overlap_mem [0:1151];
// Explicit zero init, not left implicit: unlike every other array in this
// module (buf_a/buf_b/out_buf), overlap_mem is READ on a position's very
// first access, before anything has ever written it -- an uninitialized
// (X in simulation, undefined on real BRAM at power-up) read there
// X-propagates through the combine addition (windowed_reg + ov_rd),
// poisoning every output sample for the first channel to touch each
// position. Found via simulation showing every value of the very first
// processed channel come out undefined. Quartus synthesizes this
// initial-value for-loop as a BRAM with an all-zero .mif, same mechanism
// as $readmemh elsewhere in this project, not as a runtime reset (a
// 1152-entry clear-on-reset sequence would cost real cycles every reset
// for no benefit beyond what a one-time initial value already gives).
integer ov_init_i;
initial begin
    for (ov_init_i = 0; ov_init_i < 1152; ov_init_i = ov_init_i + 1)
        overlap_mem[ov_init_i] = 32'sd0;
end
// ov_addr must be purely combinational, driven directly from out_i/
// overlap_base -- NOT a registered assignment set inside S_COMBINE_ISSUE
// (an earlier version did that). With a registered address, the dedicated
// read process below (which itself reads whatever ov_addr held BEFORE
// this same clock edge, same as every other read in this project) would
// always see the PREVIOUS iteration's address, one full combine-step
// stale -- ov_rd used during S_COMBINE_WRITE would reflect out_i-1's
// overlap position, not the current out_i's. Found via simulation: only
// the very first-ever access showed as literally undefined (X, since
// ov_addr itself hadn't been set to anything yet), but the same
// off-by-one silently affected every other access too, just masked by
// this test content's overlap values mostly being zero. Combinational
// addressing means the read initiated during S_COMBINE_ISSUE (this
// cycle's out_i) is exactly what's ready by S_COMBINE_WRITE (next cycle).
wire [10:0] ov_read_addr = overlap_base + {5'd0, out_i};
wire [10:0] ov_save_addr = overlap_base + {5'd0, out_i - 6'd18};
wire [10:0] ov_addr = (out_i < 6'd18) ? ov_read_addr : ov_save_addr;
reg ov_wr_en;
reg signed [31:0] ov_wr_data;
reg signed [31:0] ov_rd;
always @(posedge clk) begin
    if (ov_wr_en) overlap_mem[ov_addr] <= ov_wr_data;
    ov_rd <= overlap_mem[ov_addr];
end

localparam
    S_WAIT_TRIGGER  = 0,
    S_SB_INIT       = 1,
    S_MAC_ISSUE     = 2, S_MAC_ACC = 3,
    S_COMBINE_ISSUE = 4, S_COMBINE_WRITE = 5,
    S_OUT_I_NEXT    = 6,
    S_SB_NEXT       = 7,
    S_STREAM_READ   = 8, S_STREAM_EMIT = 9;

reg [3:0] state;
reg [5:0] sb;           // 0..31, current subband
reg [5:0] out_i;        // 0..35, current IMDCT output tap within this subband
reg [4:0] k;            // 0..17, MAC inner-loop index
reg signed [63:0] acc;
reg signed [31:0] windowed_reg;
reg [10:0] overlap_base; // channel*576 + sb*18, fixed for the whole subband
reg [9:0] stream_pos;

// Every subband goes through the same MAC loop (short-block subbands
// included, per the module header comment) -- only the coefficient table
// selection differs. A subband uses the long/normal (bt_sel 0) window
// either because the whole granule isn't short at all (folded into
// active_bt_sel already, via bt_sel_of), or -- for a mixed block -- it's
// one of the first active_long_end subbands that mixed blocks always
// treat as long/normal-windowed regardless of the overall short-block
// context. Any other subband of a short/mixed granule uses the short
// combined table (bt_sel 3).
wire [1:0] cur_bt_sel = (active_is_short && sb < active_long_end) ? 2'd0 :
                        active_is_short ? 2'd3 :
                        active_bt_sel;
// 12 bits: addresses now range 0..2591 (4 bt_sel variants x 648), which
// overflows an 11-bit wire (max 2047) -- an earlier version of this line
// stayed 11 bits after the short-block table was added as bt_sel=3,
// silently wrapping every address >= 2048 back into bt_sel 0's table and
// corrupting short-block subbands with garbage from unrelated ROM rows.
// Caught by comparing RTL against tools/mp3_imdct_reference.py on a real
// short-block granule: low out_i values (small addresses) matched, higher
// ones didn't, pointing straight at an address wraparound rather than a
// math error.
wire [11:0] rom_addr = {6'd0, cur_bt_sel} * 12'd648 + {6'd0, out_i} * 12'd18 + {7'd0, k};
wire [9:0] fetch_addr = {4'd0, sb} * 10'd18 + {5'd0, k};

reg [9:0] fsm_addr;
always @* begin
    fsm_addr = 10'd0;
    if (state == S_MAC_ISSUE || state == S_MAC_ACC) fsm_addr = fetch_addr;
    else if (state == S_STREAM_READ) fsm_addr = stream_pos;
end

// Each physical buffer gets its own dedicated registered read; the
// already-registered outputs are muxed afterward as a separate
// combinational step -- muxing raw memory outputs together instead breaks
// Quartus's synchronous-read RAM inference (the mp3_stereo lesson, see
// that module's header comment).
reg signed [31:0] buf_a_rd, buf_b_rd, buf_c_rd, buf_d_rd;
reg signed [31:0] fsm_rd_muxed;
always @* begin
    case (proc_bank)
        2'd0: fsm_rd_muxed = buf_a_rd;
        2'd1: fsm_rd_muxed = buf_b_rd;
        2'd2: fsm_rd_muxed = buf_c_rd;
        default: fsm_rd_muxed = buf_d_rd;
    endcase
end
wire signed [31:0] fsm_rd = fsm_rd_muxed;
reg signed [17:0] coeff_reg;

always @(posedge clk) begin
    if (wr_bank == 2'd0) begin
        if (value_valid) buf_a[value_index] <= value_data;
    end
    buf_a_rd <= buf_a[fsm_addr];

    if (wr_bank == 2'd1) begin
        if (value_valid) buf_b[value_index] <= value_data;
    end
    buf_b_rd <= buf_b[fsm_addr];

    if (wr_bank == 2'd2) begin
        if (value_valid) buf_c[value_index] <= value_data;
    end
    buf_c_rd <= buf_c[fsm_addr];

    if (wr_bank == 2'd3) begin
        if (value_valid) buf_d[value_index] <= value_data;
    end
    buf_d_rd <= buf_d[fsm_addr];

    coeff_reg <= coeff_rom[rom_addr];
end

// ob_addr is purely combinational, driven by state -- NOT set inline only
// in the write state, which would leave it stale (holding the last
// combine-phase write address) during S_STREAM_READ, reading the wrong
// out_buf position for every streamed sample. Same address-per-state
// pattern as fsm_addr above.
wire [9:0] ob_write_addr = {4'd0, out_i} * 10'd32 + {4'd0, sb};
reg [9:0] ob_addr;
always @* begin
    ob_addr = (state == S_STREAM_READ) ? stream_pos : ob_write_addr;
end
reg ob_wr_en;
reg signed [31:0] ob_wr_data;
reg signed [31:0] ob_rd;
always @(posedge clk) begin
    if (ob_wr_en) out_buf[ob_addr] <= ob_wr_data;
    ob_rd <= out_buf[ob_addr];
end

wire trigger = value_valid && value_index == 10'd575;
wire pop_now = (state == S_WAIT_TRIGGER) && (q_count != 3'd0);

wire is_odd_sb = sb[0];
// This out_i's fresh windowed value, frequency-inverted exactly once
// (applied here, at the point the value is first produced, whether it's
// used immediately or saved as overlap carry -- see
// tools/mp3_imdct_reference.py's docstring for the double-inversion bug
// this mirrors the fix for).
wire signed [31:0] windowed_val = (is_odd_sb && out_i[0]) ? -round_shift16(acc) : round_shift16(acc);

always @(posedge clk) begin
    out_valid <= 0;
    ob_wr_en <= 0;
    ov_wr_en <= 0;

    if (reset) begin
        state <= S_WAIT_TRIGGER;
        wr_bank <= 0;
        q_count <= 0; q_head <= 0; q_tail <= 0;
    end else begin
        if (trigger) begin
            q_bank[q_tail] <= wr_bank;
            q_gci[q_tail] <= value_gci;
            q_wsf[q_tail] <= value_wsf;
            q_bt[q_tail]  <= value_bt;
            q_mbf[q_tail] <= value_mbf;
            q_tail <= q_tail + 2'd1;
            wr_bank <= wr_bank + 2'd1;
        end
        q_count <= q_count + (trigger ? 3'd1 : 3'd0) - (pop_now ? 3'd1 : 3'd0);
        if (pop_now) q_head <= q_head + 2'd1;

        case (state)
        S_WAIT_TRIGGER: if (pop_now) begin
            proc_bank <= q_bank[q_head];
            active_gci <= q_gci[q_head];
            active_bt_sel <= bt_sel_of(q_wsf[q_head], q_bt[q_head]);
            active_is_short <= q_wsf[q_head] && q_bt[q_head] == 2'd2;
            active_long_end <= q_mbf[q_head] ? 6'd2 : 6'd0; // only meaningful when active_is_short
            sb <= 0;
            state <= S_SB_INIT;
        end

        S_SB_INIT: begin
            out_i <= 0;
            k <= 0;
            acc <= 64'sd0;
            overlap_base <= {5'd0, active_gci[0]} * 11'd576 + {5'd0, sb} * 11'd18;
            state <= S_MAC_ISSUE;
        end

        S_MAC_ISSUE: state <= S_MAC_ACC;
        S_MAC_ACC: begin
            acc <= acc + fsm_rd * coeff_reg;
            if (k == 5'd17) begin
                state <= S_COMBINE_ISSUE;
            end else begin
                k <= k + 5'd1;
                state <= S_MAC_ISSUE;
            end
        end

        S_COMBINE_ISSUE: begin
            if (out_i < 6'd18) begin
                windowed_reg <= windowed_val;
                state <= S_COMBINE_WRITE;
            end else begin
                ov_wr_en <= 1'b1;
                ov_wr_data <= windowed_val;
                state <= S_OUT_I_NEXT;
            end
        end
        S_COMBINE_WRITE: begin
            // ob_addr is driven combinationally (= ob_write_addr in this
            // state); only the enable/data need setting here.
            ob_wr_en <= 1'b1;
            ob_wr_data <= windowed_reg + ov_rd;
            state <= S_OUT_I_NEXT;
        end

        S_OUT_I_NEXT: begin
            if (out_i == 6'd35) begin
                out_i <= 0;
                state <= S_SB_NEXT;
            end else begin
                out_i <= out_i + 6'd1;
                k <= 0;
                acc <= 64'sd0;
                state <= S_MAC_ISSUE;
            end
        end

        S_SB_NEXT: begin
            if (sb == 6'd31) begin
                stream_pos <= 0;
                state <= S_STREAM_READ;
            end else begin
                sb <= sb + 6'd1;
                state <= S_SB_INIT;
            end
        end

        S_STREAM_READ: state <= S_STREAM_EMIT;
        S_STREAM_EMIT: begin
            out_valid <= 1;
            out_gci <= active_gci;
            out_index <= stream_pos;
            out_data <= ob_rd;
            if (stream_pos == 10'd575) begin
                state <= S_WAIT_TRIGGER;
            end else begin
                stream_pos <= stream_pos + 10'd1;
                state <= S_STREAM_READ;
            end
        end

        default: state <= S_WAIT_TRIGGER;
        endcase
    end
end

endmodule
