// Alias reduction (antialiasing butterfly), transcribed from FFmpeg's
// compute_antialias() (mpegaudiodec_template.c) -- see
// tools/mp3_antialias_reference.py for the derivation (including where
// the standard ISO 11172-3 antialiasing coefficients come from) and
// docs/MP3.md for the validation writeup.
//
// Architecture: like mp3_stereo, this cannot be a simple 1-value-per-cycle
// streaming pass -- each butterfly reads 8 values below a subband boundary
// and 8 values above it, so the whole 576-value channel must be buffered
// before any boundary can be processed. Also like mp3_stereo,
// mp3_stereo's own output has no backpressure and processes channel 0
// fully before starting channel 1 (never overlapping in time), but this
// module's own buffer+process+stream cycle can take longer per channel
// than mp3_stereo takes to produce the next one, so the same double-
// buffer + pending-channel queue design is used here, sized 2 deep to
// match mp3_stereo's own per-frame worst case (up to 4 channel
// completions per frame for stereo content).
//
// window_switching_flag/block_type/mixed_block_flag arrive ALONGSIDE the
// value stream (value_wsf/value_bt/value_mbf, from mp3_stereo's own
// out_wsf/out_bt/out_mbf) rather than being re-derived from the shared
// per-frame arrays mp3_frame_parser exposes. This module's input
// (mp3_stereo's output) can lag frame_valid by many frames' worth of
// processing time, unlike mp3_dequant's bounded few-cycle pipeline lag --
// reading window_switching_flag[value_gci] fresh from mp3_frame_parser
// here read a NEWER frame's value than the one value_data actually
// belonged to, once the lag grew past one frame. Found via comparison
// against tools/mp3_antialias_reference.py showing a pure-short-block
// granule (which should skip antialiasing entirely) getting silently
// antialiased anyway -- see docs/MP3.md.
module mp3_antialias (
    input wire clk, reset,

    input wire value_valid,
    input wire [1:0] value_gci,
    input wire [9:0] value_index,
    input wire signed [31:0] value_data,
    input wire value_wsf,
    input wire [1:0] value_bt,
    input wire value_mbf,

    output reg out_valid,
    output reg [1:0] out_gci,
    output reg [9:0] out_index,
    output reg signed [31:0] out_data,
    output reg out_wsf,
    output reg [1:0] out_bt,
    output reg out_mbf,

    // True when nothing is in progress or queued -- see mp3_stereo.sv's
    // header comment on this same port for the real-hardware pacing need.
    output wire idle
);

// Number of subband boundaries to process (see module header / reference):
// pure short blocks skip antialiasing entirely, mixed blocks only process
// the first boundary (the only "long" one), everything else processes all
// 31 internal boundaries of the 32 18-sample subbands making up the
// 576-value spectrum.
function [5:0] num_boundaries_of;
    input wsf; input [1:0] bt; input mbf;
    begin
        if (wsf && bt == 2'd2) num_boundaries_of = mbf ? 6'd1 : 6'd0;
        else num_boundaries_of = 6'd31;
    end
endfunction

// Q0.20 fixed point, derived directly from cs[j]=1/sqrt(1+c[j]^2),
// ca[j]=c[j]*cs[j] where c is the standard ISO 11172-3 antialiasing
// coefficient table -- see tools/mp3_antialias_reference.py.
localparam AA_FRAC_BITS = 20;
function signed [20:0] cs_table;
    input [2:0] j;
    begin
        case (j)
            3'd0: cs_table = 21'sd899147;
            3'd1: cs_table = 21'sd924573;
            3'd2: cs_table = 21'sd995758;
            3'd3: cs_table = 21'sd1031080;
            3'd4: cs_table = 21'sd1043876;
            3'd5: cs_table = 21'sd1047696;
            3'd6: cs_table = 21'sd1048470;
            default: cs_table = 21'sd1048569;
        endcase
    end
endfunction
function signed [20:0] ca_table;
    input [2:0] j;
    begin
        case (j)
            3'd0: ca_table = -21'sd539488;
            3'd1: ca_table = -21'sd494647;
            3'd2: ca_table = -21'sd328600;
            3'd3: ca_table = -21'sd190750;
            3'd4: ca_table = -21'sd99168;
            3'd5: ca_table = -21'sd42956;
            3'd6: ca_table = -21'sd14888;
            default: ca_table = -21'sd3880;
        endcase
    end
endfunction

function signed [31:0] round_shift21;
    input signed [63:0] acc;
    begin
        if (acc >= 0)
            round_shift21 = (acc + (64'sd1 <<< (AA_FRAC_BITS - 1))) >>> AA_FRAC_BITS;
        else
            round_shift21 = -((-acc + (64'sd1 <<< (AA_FRAC_BITS - 1))) >>> AA_FRAC_BITS);
    end
endfunction

// -- Double-buffered per-channel storage, with a 2-deep pending queue,
// same structural reasoning as mp3_stereo.sv (see its header comment for
// the full rationale, including the two bugs found there that this
// module was written to avoid from the start: querying wr_bank/proc_bank
// independently rather than assuming one is the other's complement, and
// giving each physical bank array its own dedicated registered read
// output rather than muxing two memories' outputs into one register). --
reg signed [31:0] buf_a [0:575], buf_b [0:575];
reg wr_bank;
reg proc_bank;

reg q_bank [0:1];
reg [1:0] q_gci [0:1];
reg q_wsf [0:1]; reg [1:0] q_bt [0:1]; reg q_mbf [0:1];
reg [1:0] q_count;
reg q_head, q_tail;

reg [1:0] active_gci;
reg active_wsf; reg [1:0] active_bt; reg active_mbf;

localparam
    S_WAIT_TRIGGER = 0,
    S_AA_SIZE      = 1,
    S_AA_READ_LO   = 2, S_AA_READ_HI = 3,
    S_AA_WRITE_LO  = 4, S_AA_WRITE_HI = 5,
    S_AA_NEXT      = 6,
    S_STREAM_READ  = 7, S_STREAM_EMIT = 8;

reg [3:0] state;
assign idle = (state == 4'd0) && (q_count == 2'd0);
reg [5:0] num_boundaries;
reg [5:0] boundary_i;   // 0..num_boundaries-1
reg [2:0] tap_j;        // 0..7
reg [9:0] stream_pos;
reg signed [31:0] rd_lo, rd_hi;

wire [9:0] boundary_pos = {4'd0, boundary_i + 6'd1} * 10'd18; // 18*(boundary_i+1)
wire [9:0] lo_addr = boundary_pos - 10'd1 - {7'd0, tap_j};
wire [9:0] hi_addr = boundary_pos + {7'd0, tap_j};

wire signed [63:0] new_lo_acc = rd_lo * cs_table(tap_j) - fsm_rd * ca_table(tap_j);
wire signed [63:0] new_hi_acc = rd_lo * ca_table(tap_j) + rd_hi * cs_table(tap_j);

reg [9:0] fsm_addr;
reg fsm_wr_en;
reg signed [31:0] fsm_wr_data;
always @* begin
    fsm_addr = 10'd0;
    fsm_wr_en = 1'b0;
    fsm_wr_data = 32'sd0;
    case (state)
        S_AA_READ_LO: fsm_addr = lo_addr;
        S_AA_READ_HI: fsm_addr = hi_addr;
        S_AA_WRITE_LO: begin
            fsm_addr = lo_addr;
            fsm_wr_en = 1'b1;
            fsm_wr_data = round_shift21(new_lo_acc);
        end
        S_AA_WRITE_HI: begin
            fsm_addr = hi_addr;
            fsm_wr_en = 1'b1;
            fsm_wr_data = round_shift21(new_hi_acc);
        end
        S_STREAM_READ: fsm_addr = stream_pos;
        default: ;
    endcase
end

reg signed [31:0] buf_a_rd, buf_b_rd;
wire signed [31:0] fsm_rd = (proc_bank == 1'b0) ? buf_a_rd : buf_b_rd;

always @(posedge clk) begin
    if (wr_bank == 1'b0) begin
        if (value_valid) buf_a[value_index] <= value_data;
    end else if (proc_bank == 1'b0) begin
        if (fsm_wr_en) buf_a[fsm_addr] <= fsm_wr_data;
    end
    buf_a_rd <= buf_a[fsm_addr];

    if (wr_bank == 1'b1) begin
        if (value_valid) buf_b[value_index] <= value_data;
    end else if (proc_bank == 1'b1) begin
        if (fsm_wr_en) buf_b[fsm_addr] <= fsm_wr_data;
    end
    buf_b_rd <= buf_b[fsm_addr];
end

wire trigger = value_valid && value_index == 10'd575;
wire pop_now = (state == S_WAIT_TRIGGER) && (q_count != 2'd0);

always @(posedge clk) begin
    out_valid <= 0;

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
            q_tail <= ~q_tail;
            wr_bank <= ~wr_bank;
        end
        q_count <= q_count + (trigger ? 2'd1 : 2'd0) - (pop_now ? 2'd1 : 2'd0);
        if (pop_now) q_head <= ~q_head;

        case (state)
        S_WAIT_TRIGGER: if (pop_now) begin
            proc_bank <= q_bank[q_head];
            active_gci <= q_gci[q_head];
            active_wsf <= q_wsf[q_head]; active_bt <= q_bt[q_head]; active_mbf <= q_mbf[q_head];
            num_boundaries <= num_boundaries_of(q_wsf[q_head], q_bt[q_head], q_mbf[q_head]);
            boundary_i <= 0;
            tap_j <= 0;
            state <= S_AA_SIZE;
        end

        S_AA_SIZE: begin
            if (num_boundaries == 6'd0) begin
                stream_pos <= 0;
                state <= S_STREAM_READ;
            end else begin
                state <= S_AA_READ_LO;
            end
        end

        S_AA_READ_LO: state <= S_AA_READ_HI;
        S_AA_READ_HI: begin
            rd_lo <= fsm_rd; // lo's data, valid this cycle from S_AA_READ_LO's address
            state <= S_AA_WRITE_LO;
        end
        S_AA_WRITE_LO: begin
            rd_hi <= fsm_rd; // hi's data, valid this cycle from S_AA_READ_HI's address
            state <= S_AA_WRITE_HI;
        end
        S_AA_WRITE_HI: begin
            if (tap_j == 3'd7) begin
                tap_j <= 0;
                state <= S_AA_NEXT;
            end else begin
                tap_j <= tap_j + 3'd1;
                state <= S_AA_READ_LO;
            end
        end

        S_AA_NEXT: begin
            if (boundary_i == num_boundaries - 6'd1) begin
                stream_pos <= 0;
                state <= S_STREAM_READ;
            end else begin
                boundary_i <= boundary_i + 6'd1;
                state <= S_AA_READ_LO;
            end
        end

        S_STREAM_READ: state <= S_STREAM_EMIT;
        S_STREAM_EMIT: begin
            out_valid <= 1;
            out_gci <= active_gci;
            out_index <= stream_pos;
            out_data <= fsm_rd;
            out_wsf <= active_wsf; out_bt <= active_bt; out_mbf <= active_mbf;
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
