// Polyphase synthesis filterbank (step 8): converts 32 IMDCT subband
// samples per time slot into 32 interleaved PCM samples per time slot,
// per ISO/IEC 11172-3's direct synthesis subband filter definition (the
// same algorithm shared by Layer I/II/III -- MP3's own contribution ends
// at the IMDCT, this stage is unmodified spec machinery). Implemented
// from the direct O(64*32 + 512) definition, not FFmpeg's fast algorithm
// (a hand-factorized 32-point DCT-III fused with a circular-buffer
// trick) -- see tools/mp3_synthesis_reference.py's module docstring for
// the full derivation and how the matrixing formula and the window
// table's absolute scale were each independently confirmed against real
// FFmpeg output (not trusted from memory/general knowledge alone).
//
// Matrixing: V[i] = round(sum_k(S[k] * cos((16+i)*(2k+1)*pi/64)), 16),
// i=0..63, k=0..31, for the 32 fresh subband samples of one time slot.
// Windowing: for each of the 32 output samples j, sum 16 terms drawn from
// V's persistent 1024-entry-per-channel history (8 pairs, each pair
// combining V at logical positions (128m+j) and (128m+96+j), m=0..7, with
// window coefficients at (64m+j) and (64m+32+j) respectively -- this is
// the direct algebraic simplification of the ISO pseudocode's "V shift,
// U extract, D window multiply, 16-term sum" into one indexing scheme
// without materializing the intermediate U array, worked out by hand;
// see the reference model for the derivation), rounded ONCE by 24 bits at
// the very end (not per-term, avoiding the double-rounding bug class
// already hit once in mp3_antialias_reference.py).
//
// Persistent V history is the SECOND kind of state in this project that
// survives indefinitely (after mp3_imdct's overlap_mem), but a new kind:
// it's the primary working data itself, not an add-on correction -- every
// PCM sample depends on up to 16 of its channel's most recent time slots,
// not just the current one. Implemented as a genuine circular buffer (a
// per-channel "base" pointer that decrements by 64, mod 1024, each time
// slot) rather than a literal 1024-wide shift register: writing the fresh
// 64 values at the new base position and simply moving the base pointer
// achieves the same effect as shifting 960 old values, at zero extra
// hardware cost per shift.
//
// Architecture: like every stage since mp3_stereo, this module's own
// processing time per unit of work dramatically exceeds its input's
// production rate -- worse here than anywhere else in the pipeline. One
// time slot's ~64*32 matrixing MACs plus ~32*16 windowing MACs (~3,100
// serial MAC cycles total) is slower than mp3_imdct can stream out a
// full 576-value channel (18 time slots) to it. A full stereo frame can
// therefore complete production of all 2 granules x 2 channels x 18 time
// slots = 72 time slots before this module finishes draining even the
// first one -- the true worst case for this fixed profile (bounded, not
// unbounded, because a new frame's data can't start arriving until the
// current frame fully drains through the whole pipeline in real
// operation, per the same bit-rate-limited-pacing argument established
// for mp3_imdct's own 4-deep buffering). Sized accordingly: a 72-entry
// pending queue, each entry a full 32-value time slot, backed by one
// flat 2304-value (72*32) circular buffer rather than 72 separate
// 32-entry buffers (equivalent capacity, one shared address space).
module mp3_synthesis (
    input wire clk, reset,

    input wire value_valid,
    input wire [1:0] value_gci,
    input wire [9:0] value_index,   // 0..575 from mp3_imdct, t*32+sb
    input wire signed [31:0] value_data,

    // One pulse per PCM sample: out_sample is this time slot's output
    // position (0..31); a full channel's audio is out_gci's consecutive
    // time slots' streams concatenated in arrival order.
    output reg out_valid,
    output reg [1:0] out_gci,
    output reg [4:0] out_sample,
    output reg signed [15:0] out_data,

    // True when nothing is in progress or queued -- see mp3_stereo.sv's
    // header comment on this same port for the real-hardware pacing need.
    output wire idle
);

localparam MFRAC = 16;   // matrixing coefficient fixed-point fractional bits
localparam WFRAC = 24;   // final shift after the window-multiply 16-term sum -- see tools/mp3_synthesis_reference.py

reg signed [17:0] matrix_rom [0:2047];  // 64 x 32, flat index i*32+k
initial $readmemh("rtl/mp3_synthesis_matrix.hex", matrix_rom);
reg signed [17:0] window_rom [0:511];
initial $readmemh("rtl/mp3_synthesis_window.hex", window_rom);

function signed [31:0] round_shift16;
    input signed [63:0] acc;
    begin
        if (acc >= 0) round_shift16 = (acc + (64'sd1 <<< 15)) >>> 16;
        else round_shift16 = -((-acc + (64'sd1 <<< 15)) >>> 16);
    end
endfunction

function signed [31:0] round_shift24;
    input signed [63:0] acc;
    begin
        if (acc >= 0) round_shift24 = (acc + (64'sd1 <<< 23)) >>> 24;
        else round_shift24 = -((-acc + (64'sd1 <<< 23)) >>> 24);
    end
endfunction

function signed [15:0] clip16;
    input signed [31:0] v;
    begin
        if (v > 32'sd32767) clip16 = 16'sd32767;
        else if (v < -32'sd32768) clip16 = 16'sh8000;
        else clip16 = v[15:0];
    end
endfunction

// -- Pending time-slot queue: one flat 2304-entry (72*32) circular buffer
// -- rather than 72 physically separate 32-entry buffers, since every
// entry is read/written through the same simple sequential-address
// pattern regardless of which logical slot it belongs to.
reg signed [31:0] pending_buf [0:2303];
reg [11:0] wr_ptr;
reg [1:0] q_gci [0:71];
reg [6:0] q_count;
reg [6:0] q_head, q_tail;

wire trigger = value_valid && (value_index[4:0] == 5'd31);
wire pop_now = (state_is_wait) && (q_count != 7'd0);

// -- Persistent per-channel V history (1024 entries each), a genuine
// circular buffer via a per-channel base pointer -- see module header.
reg signed [31:0] v_mem0 [0:1023];
reg signed [31:0] v_mem1 [0:1023];
reg [9:0] v_base0, v_base1;
integer v_init_i;
initial begin
    for (v_init_i = 0; v_init_i < 1024; v_init_i = v_init_i + 1) begin
        v_mem0[v_init_i] = 32'sd0;
        v_mem1[v_init_i] = 32'sd0;
    end
    v_base0 = 10'd0;
    v_base1 = 10'd0;
end

localparam
    S_WAIT_TRIGGER = 0,
    S_MATRIX_ISSUE = 1, S_MATRIX_ACC = 2,
    S_MATRIX_WRITE = 3,
    S_MATRIX_NEXT  = 4,
    S_WIN_ISSUE    = 5, S_WIN_ACC = 6,
    S_WIN_EMIT     = 7,
    S_WIN_NEXT     = 8;

reg [3:0] state;
assign idle = (state == 4'd0) && (q_count == 7'd0);
wire state_is_wait = (state == S_WAIT_TRIGGER);

reg [1:0] active_gci;
reg [11:0] active_slot_base;
wire v_base_active_channel = active_gci[0];
wire [9:0] v_base_active = v_base_active_channel ? v_base1 : v_base0;

reg [5:0] i;   // 0..63, matrixing output tap
reg [4:0] k;   // 0..31, matrixing input subband
reg [4:0] j;   // 0..31, window output sample
reg [2:0] m;   // 0..7, window sum pair index
reg term;      // 0/1, which of the pair's two terms
reg signed [63:0] acc;

// -- pending_buf: one write process (upstream streaming in), one
// dedicated registered read (this module's own matrix-phase fetch) --
// simple dual-port, the RAM-inference-safe pattern established since
// mp3_stereo's header comment.
wire [11:0] pending_rd_addr = active_slot_base + {7'd0, k};
reg signed [31:0] pending_rd;
always @(posedge clk) begin
    if (value_valid) pending_buf[wr_ptr] <= value_data;
    pending_rd <= pending_buf[pending_rd_addr];
end

// -- matrix_rom/window_rom addressing: combinational, driven by state,
// never a registered assignment inside an FSM state body -- the mp3_imdct
// lesson (a registered address makes the dedicated read one cycle stale).
wire [10:0] matrix_addr = {i, k};
wire [9:0] win_v_offset = term ? ({m, 7'b0} + 10'd96 + {5'd0, j}) : ({m, 7'b0} + {5'd0, j});
wire [8:0] win_rom_addr = term ? ({m, 6'b0} + 9'd32 + {4'd0, j}) : ({m, 6'b0} + {4'd0, j});

reg [10:0] mrom_addr;
reg [8:0] wrom_addr;
always @* begin
    mrom_addr = 11'd0;
    wrom_addr = 9'd0;
    if (state == S_MATRIX_ISSUE || state == S_MATRIX_ACC) mrom_addr = matrix_addr;
    else if (state == S_WIN_ISSUE || state == S_WIN_ACC) wrom_addr = win_rom_addr;
end
reg signed [17:0] mrom_reg, wrom_reg;
always @(posedge clk) begin
    mrom_reg <= matrix_rom[mrom_addr];
    wrom_reg <= window_rom[wrom_addr];
end

// -- v_mem0/v_mem1: one write process each, one dedicated registered read
// each, muxed as a separate combinational step afterward -- same
// discipline as every RAM in this project since mp3_stereo. v_wr_en and
// v_wr_data must ALSO be combinational here, not registered pulses set
// "on entering" S_MATRIX_WRITE the way an earlier draft had them: v_addr
// is combinational on `state` itself, so it changes THE INSTANT state
// becomes S_MATRIX_WRITE, but a registered `v_wr_en <= 1` set inside that
// same state's body doesn't actually take effect until ONE CYCLE LATER --
// by which point state has already moved on to S_MATRIX_NEXT and v_addr
// has already reverted to its default (0). Every V write was landing at
// address 0 instead of its intended v_base+i, one cycle after v_addr had
// already moved off that address -- found by tracing a specific write
// (SYNTHV showed the correct address/data being computed) against a
// later read at that same address coming back as stale/zero (SYNTHW),
// then confirming the write's enable and address were simply never true
// at the same cycle. Different from (though related to) the mp3_imdct
// ov_addr lesson: there, the address depended on a counter (out_i) that
// changes in a LATER state than where its write-enable is set, so no
// misalignment; here the address depended on `state` itself, the same
// signal whose transition is what delays a registered enable by a cycle.
// General lesson: a write-enable derived from "we just entered state X"
// must be combinational (state==X) whenever the address is ALSO a
// combinational function of that same state -- a registered version of
// either one, mixed with a combinational version of the other, misaligns
// by exactly one cycle.
reg [9:0] v_addr;
always @* begin
    v_addr = 10'd0;
    case (state)
        S_MATRIX_WRITE: v_addr = v_base_active + {4'd0, i};
        S_WIN_ISSUE, S_WIN_ACC: v_addr = v_base_active + win_v_offset;
        default: ;
    endcase
end
wire v_wr_en = (state == S_MATRIX_WRITE);
wire signed [31:0] v_wr_data = round_shift16(acc);
reg signed [31:0] v0_rd, v1_rd;
always @(posedge clk) begin
    if (v_wr_en && !v_base_active_channel) v_mem0[v_addr] <= v_wr_data;
    v0_rd <= v_mem0[v_addr];
    if (v_wr_en && v_base_active_channel) v_mem1[v_addr] <= v_wr_data;
    v1_rd <= v_mem1[v_addr];
end
wire signed [31:0] v_rd = v_base_active_channel ? v1_rd : v0_rd;

always @(posedge clk) begin
    out_valid <= 0;

    if (reset) begin
        state <= S_WAIT_TRIGGER;
        wr_ptr <= 12'd0;
        q_count <= 7'd0; q_head <= 7'd0; q_tail <= 7'd0;
    end else begin
        if (value_valid) wr_ptr <= (wr_ptr == 12'd2303) ? 12'd0 : wr_ptr + 12'd1;
        if (trigger) begin
            q_gci[q_tail] <= value_gci;
            q_tail <= (q_tail == 7'd71) ? 7'd0 : q_tail + 7'd1;
        end
        q_count <= q_count + (trigger ? 7'd1 : 7'd0) - (pop_now ? 7'd1 : 7'd0);

        case (state)
        S_WAIT_TRIGGER: if (pop_now) begin
            active_gci <= q_gci[q_head];
            active_slot_base <= {q_head, 5'b0};
            if (q_gci[q_head][0]) v_base1 <= v_base1 - 10'd64;
            else v_base0 <= v_base0 - 10'd64;
            q_head <= (q_head == 7'd71) ? 7'd0 : q_head + 7'd1;
            i <= 0; k <= 0; acc <= 64'sd0;
            state <= S_MATRIX_ISSUE;
        end

        S_MATRIX_ISSUE: state <= S_MATRIX_ACC;
        S_MATRIX_ACC: begin
            acc <= acc + pending_rd * mrom_reg;
            if (k == 5'd31) state <= S_MATRIX_WRITE;
            else begin
                k <= k + 5'd1;
                state <= S_MATRIX_ISSUE;
            end
        end
        S_MATRIX_WRITE: begin
            state <= S_MATRIX_NEXT;
        end
        S_MATRIX_NEXT: begin
            if (i == 6'd63) begin
                j <= 0; m <= 0; term <= 0; acc <= 64'sd0;
                state <= S_WIN_ISSUE;
            end else begin
                i <= i + 6'd1;
                k <= 0; acc <= 64'sd0;
                state <= S_MATRIX_ISSUE;
            end
        end

        S_WIN_ISSUE: state <= S_WIN_ACC;
        S_WIN_ACC: begin
            acc <= acc + v_rd * wrom_reg;
            if (m == 3'd7 && term == 1'b1) state <= S_WIN_EMIT;
            else begin
                if (term == 1'b1) begin
                    m <= m + 3'd1;
                    term <= 1'b0;
                end else begin
                    term <= 1'b1;
                end
                state <= S_WIN_ISSUE;
            end
        end
        S_WIN_EMIT: begin
            out_valid <= 1'b1;
            out_gci <= active_gci;
            out_sample <= j;
            out_data <= clip16(round_shift24(acc));
            state <= S_WIN_NEXT;
        end
        S_WIN_NEXT: begin
            if (j == 5'd31) begin
                state <= S_WAIT_TRIGGER;
            end else begin
                j <= j + 5'd1;
                m <= 0; term <= 0; acc <= 64'sd0;
                state <= S_WIN_ISSUE;
            end
        end

        default: state <= S_WAIT_TRIGGER;
        endcase
    end
end

endmodule
