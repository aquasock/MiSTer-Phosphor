// MPEG-1 Layer III requantization (dequantization).
//
// Converts mp3_huffman_decoder's raw Huffman-decoded integers into
// unscaled real-valued spectral magnitudes, per ISO/IEC 11172-3's
// is[i]^(4/3) * 2^(exponent[i]/4) formula. The exponent-from-scale-factor
// formula is transcribed from FFmpeg's exponents_from_scale_factors()
// (see docs/MP3.md); the fixed-point table/multiply scheme is this
// project's own design, not FFmpeg's -- see tools/mp3_dequant_rom_gen.py
// for why (FFmpeg's combined table trades 4x the ROM size to avoid a
// multiply, backwards for an FPGA with idle DSP blocks).
//
// Architecture note: this module does NOT expand each scale-factor band's
// exponent across all the frequency positions it covers into a flat
// 576-entry array. A single band can cover up to ~190 positions, and
// filling that many entries one per cycle would fall behind
// mp3_huffman_decoder's scale-factor stream (which advances every few
// cycles) -- the same class of race already found and fixed once this
// project (frame parser vs. Huffman decoder). Instead, one exponent value
// is stored per scale-factor band (a small ~39-entry array, O(1) per
// sf_valid event), and the value-consuming side independently tracks
// which band boundary the strictly-increasing value_index has reached,
// advancing with a single comparison per value -- neither side's timing
// depends on the other's.
module mp3_dequant (
    input wire clk, reset,

    input wire frame_valid,
    input wire sample_rate_44k1,
    input wire window_switching_flag [0:3],
    input wire [1:0] block_type [0:3],
    input wire mixed_block_flag [0:3],
    input wire [7:0] global_gain [0:3],
    input wire scalefac_scale [0:3],
    input wire preflag [0:3],
    input wire [2:0] subblock_gain [0:3][0:2],

    // From mp3_huffman_decoder.
    input wire sf_valid,
    input wire [1:0] sf_gci,
    input wire [5:0] sf_index,
    input wire [3:0] sf_data,
    input wire value_valid,
    input wire [1:0] value_gci,
    input wire [9:0] value_index,
    input wire signed [15:0] value_data,

    // Dequantized spectral coefficients, one per input value_valid (same
    // 576-per-granule/channel cadence), fixed-point scale 2^23 relative to
    // the true mathematical magnitude.
    output reg out_valid,
    output reg [1:0] out_gci,
    output reg [9:0] out_index,
    output reg signed [31:0] out_data
);

localparam OUTPUT_SCALE_BITS = 23;
localparam FRAC_BITS_TABLE = 17;
localparam MAG43_FRAC_BITS = 6;
// OUTPUT_SCALE_BITS - FRAC_BITS_TABLE - MAG43_FRAC_BITS = 0 by construction
// (see tools/mp3_dequant_reference.py) -- the post-multiply shift amount
// is exactly the exponent's integer part (>>>2), no extra additive constant.

reg l_window_switching_flag [0:3];
reg [1:0] l_block_type [0:3];
reg l_mixed_block_flag [0:3];
reg [7:0] l_global_gain [0:3];
reg l_scalefac_scale [0:3];
reg l_preflag [0:3];
reg [2:0] l_subblock_gain [0:3][0:2];
reg l_sample_rate_44k1;

integer li;
always @(posedge clk) begin
    if (frame_valid) begin
        l_sample_rate_44k1 <= sample_rate_44k1;
        for (li = 0; li < 4; li = li + 1) begin
            l_window_switching_flag[li] <= window_switching_flag[li];
            l_block_type[li] <= block_type[li];
            l_mixed_block_flag[li] <= mixed_block_flag[li];
            l_global_gain[li] <= global_gain[li];
            l_scalefac_scale[li] <= scalefac_scale[li];
            l_preflag[li] <= preflag[li];
            l_subblock_gain[li][0] <= subblock_gain[li][0];
            l_subblock_gain[li][1] <= subblock_gain[li][1];
            l_subblock_gain[li][2] <= subblock_gain[li][2];
        end
    end
end

// long_end/short_start per compute_band_indexes -- block_type is only
// meaningful when window_switching_flag=1 (see mp3_huffman_decoder.sv for
// the same gate and why: mp3_frame_parser leaves it stale otherwise).
function [5:0] long_end_of;
    input gci2; input [1:0] bt; input mbf; input wsf;
    begin
        if (wsf && bt == 2'd2) long_end_of = mbf ? 6'd8 : 6'd0;
        else long_end_of = 6'd22;
    end
endfunction
function [5:0] short_start_of;
    input gci2; input [1:0] bt; input mbf; input wsf;
    begin
        if (wsf && bt == 2'd2) short_start_of = mbf ? 6'd3 : 6'd0;
        else short_start_of = 6'd13;
    end
endfunction

wire [5:0] sf_long_end = long_end_of(1'b0, l_block_type[sf_gci], l_mixed_block_flag[sf_gci], l_window_switching_flag[sf_gci]);
wire [5:0] sf_short_start = short_start_of(1'b0, l_block_type[sf_gci], l_mixed_block_flag[sf_gci], l_window_switching_flag[sf_gci]);
wire [5:0] val_long_end = long_end_of(1'b0, l_block_type[value_gci], l_mixed_block_flag[value_gci], l_window_switching_flag[value_gci]);
wire [5:0] val_short_start = short_start_of(1'b0, l_block_type[value_gci], l_mixed_block_flag[value_gci], l_window_switching_flag[value_gci]);

// -- Band-size / pretab ROMs -----------------------------------------
reg [7:0] band_size_long_rom [0:43];   // [sample_rate][band 0..21]
reg [7:0] band_size_short_rom [0:25];  // [sample_rate][band 0..12]
reg [3:0] pretab_rom [0:21];           // preflag=1 case only; preflag=0 is always zero
initial $readmemh("rtl/mp3_dequant_band_size_long.hex", band_size_long_rom);
initial $readmemh("rtl/mp3_dequant_band_size_short.hex", band_size_short_rom);
initial $readmemh("rtl/mp3_dequant_pretab.hex", pretab_rom);
wire [5:0] long_row = l_sample_rate_44k1 ? 6'd0 : 6'd22;
wire [4:0] short_row = l_sample_rate_44k1 ? 5'd0 : 5'd13;

// -- Scale-factor-side: compute one exponent value per sf_valid event --
reg signed [9:0] band_exponent [0:38];
reg [1:0] sf_window_w;
reg [5:0] sf_short_band_i;

wire sf_is_long = sf_index < sf_long_end;
wire [7:0] sf_pretab_val = l_preflag[sf_gci] ? {4'd0, pretab_rom[sf_index[4:0]]} : 8'd0;
wire signed [9:0] sf_gain_long = $signed({2'd0, l_global_gain[sf_gci]}) - 10'sd210;
wire signed [9:0] sf_gain_short = sf_gain_long - {5'd0, l_subblock_gain[sf_gci][sf_window_w], 3'd0};
wire [1:0] sf_shift = {1'b0, l_scalefac_scale[sf_gci]} + 2'd1;
wire signed [9:0] sf_v0_long = sf_gain_long - (($signed({2'd0, sf_data}) + $signed({2'd0, sf_pretab_val})) <<< sf_shift);
wire signed [9:0] sf_v0_short = sf_gain_short - ($signed({2'd0, sf_data}) <<< sf_shift);

always @(posedge clk) begin
    if (frame_valid) begin
        // nothing to reset here; sf_index==0 (below) re-initializes per gci
    end else if (sf_valid) begin
        if (sf_index == 6'd0) begin
            sf_window_w <= 0;
            sf_short_band_i <= sf_short_start;
        end
        band_exponent[sf_index] <= sf_is_long ? sf_v0_long : sf_v0_short;
        if (!sf_is_long) begin
            if (sf_window_w == 2'd2) begin sf_window_w <= 0; sf_short_band_i <= sf_short_band_i + 6'd1; end
            else sf_window_w <= sf_window_w + 2'd1;
        end
    end
end

// -- Value-side: track which band the strictly-increasing value_index is in --
// Mirrors compute_exponents' band walk (long bands 0..long_end-1, then short
// bands short_start..12 with window 0..2 innermost) using its own pace, so it
// never has to keep up cycle-for-cycle with the sf_valid stream on the other
// side -- see module header.
reg [5:0] val_compact_idx;
reg [5:0] val_band_i;
reg [1:0] val_window_w;
reg val_is_long;
reg [7:0] val_pos_in_band;   // 0-indexed position of the in-flight value within its band
reg [5:0] val_long_end_reg;
reg [5:0] val_short_start_reg;

function [7:0] band_size_of;
    input is_long_f;
    input [5:0] band_i_f;
    begin
        if (is_long_f) band_size_of = band_size_long_rom[long_row + band_i_f];
        else band_size_of = band_size_short_rom[short_row + band_i_f];
    end
endfunction

reg [23:0] mag43_rom [0:8206];
reg [17:0] frac_exp_rom [0:3];
initial $readmemh("rtl/mp3_dequant_mag43.hex", mag43_rom);
initial $readmemh("rtl/mp3_dequant_frac_exp.hex", frac_exp_rom);

// A true 4-stage pipeline, one value accepted per cycle, no stalling: the
// count1/quad states in mp3_huffman_decoder.sv (C1_ZERO/C1_EMIT) can emit a
// new value_valid on every consecutive cycle for a run of zero-magnitude
// symbols, which is common at high frequencies in real audio. An earlier
// version of this module was a single shared 5-cycle FSM (idle -> lookup ->
// mult -> shift -> emit) reused for every value; it silently dropped any
// value_valid that arrived while busy, discovered by comparison against
// tools/mp3_dequant_reference.py showing entire runs of missing output
// indices. Each stage below advances unconditionally every cycle, carrying
// a per-value valid bit as a bubble when there's nothing to do, so no
// input can arrive faster than this module can absorb it.
wire [5:0] this_compact_idx = (value_valid && value_index == 10'd0) ? 6'd0 : val_compact_idx;

reg stage1_valid;
reg [13:0] stage1_mag;
reg stage1_sign;
reg [1:0] stage1_gci;
reg [9:0] stage1_index;
reg signed [9:0] stage1_exponent;

reg stage2_valid;
reg [23:0] stage2_m43;
reg [1:0] stage2_frac;
reg signed [9:0] stage2_int_exp;
reg stage2_sign;
reg [1:0] stage2_gci;
reg [9:0] stage2_index;

reg stage3_valid;
reg signed [47:0] stage3_product;
reg signed [9:0] stage3_int_exp;
reg stage3_sign;
reg [1:0] stage3_gci;
reg [9:0] stage3_index;

always @(posedge clk) begin
    if (reset) begin
        val_compact_idx <= 0; val_band_i <= 0; val_window_w <= 0; val_is_long <= 1;
        val_pos_in_band <= 0; val_long_end_reg <= 0; val_short_start_reg <= 0;
        stage1_valid <= 0; stage2_valid <= 0; stage3_valid <= 0; out_valid <= 0;
    end else begin : dq_pipe_blk
        reg next_is_long;
        reg [5:0] next_band_i;
        reg [1:0] next_window_w;
        reg signed [63:0] shifted;
        reg signed [63:0] rounded;
        reg [7:0] this_pos;
        reg [7:0] this_band_size;
        reg is_last_of_band;

        // Stage 0: capture the incoming value and advance the band tracker.
        //
        // this_pos/this_band_size are evaluated combinationally for the
        // value in flight *this* cycle (special-cased at value_index==0,
        // same reasoning as this_compact_idx above): comparing them here,
        // rather than checking a countdown register written on the *previous*
        // cycle, avoids an off-by-one that misattributed the first value of
        // each new band to the previous band's exponent (found by comparison
        // against tools/mp3_dequant_reference.py -- the boundary error only
        // showed up right at a band edge, e.g. long band 18/19's boundary at
        // frequency position 288 in a real test file).
        stage1_valid <= value_valid;
        if (value_valid) begin
            stage1_mag <= value_data[15] ? (-value_data) : value_data;
            stage1_sign <= value_data[15];
            stage1_gci <= value_gci;
            stage1_index <= value_index;
            stage1_exponent <= band_exponent[this_compact_idx];

            if (value_index == 10'd0) begin
                val_long_end_reg <= val_long_end;
                val_short_start_reg <= val_short_start;
                val_compact_idx <= 0;
                val_window_w <= 0;
                this_pos = 8'd0;
                if (val_long_end != 6'd0) begin
                    val_is_long <= 1'b1;
                    val_band_i <= 6'd0;
                    this_band_size = band_size_of(1'b1, 6'd0);
                end else begin
                    val_is_long <= 1'b0;
                    val_band_i <= val_short_start;
                    this_band_size = band_size_of(1'b0, val_short_start);
                end
                is_last_of_band = (this_band_size == 8'd1);
                val_pos_in_band <= is_last_of_band ? 8'd0 : 8'd1;
                // A same-cycle band change (band size 1) can't happen with
                // real MP3 band tables (minimum size 4), so no further
                // transition handling is needed here for that edge case.
            end else begin
                this_pos = val_pos_in_band;
                this_band_size = band_size_of(val_is_long, val_band_i);
                is_last_of_band = (this_pos + 8'd1 == this_band_size);
                if (is_last_of_band) begin
                    // This value was the last one covered by the current
                    // band's exponent -- advance to the next band for the
                    // value after it.
                    val_compact_idx <= val_compact_idx + 6'd1;
                    if (val_is_long) begin
                        if (val_band_i + 6'd1 == val_long_end_reg) begin
                            if (val_short_start_reg < 6'd13) begin
                                next_is_long = 1'b0;
                                next_band_i = val_short_start_reg;
                                next_window_w = 2'd0;
                            end else begin
                                next_is_long = 1'b1;
                                next_band_i = val_band_i + 6'd1;
                                next_window_w = 2'd0;
                            end
                        end else begin
                            next_is_long = 1'b1;
                            next_band_i = val_band_i + 6'd1;
                            next_window_w = 2'd0;
                        end
                    end else begin
                        next_is_long = 1'b0;
                        if (val_window_w == 2'd2) begin
                            next_band_i = val_band_i + 6'd1;
                            next_window_w = 2'd0;
                        end else begin
                            next_band_i = val_band_i;
                            next_window_w = val_window_w + 2'd1;
                        end
                    end
                    val_is_long <= next_is_long;
                    val_band_i <= next_band_i;
                    val_window_w <= next_window_w;
                    val_pos_in_band <= 8'd0;
                end else begin
                    val_pos_in_band <= this_pos + 8'd1;
                end
            end
        end

        // Stage 1 -> 2: magnitude^(4/3) table lookup.
        stage2_valid <= stage1_valid;
        if (stage1_valid) begin
            stage2_m43 <= mag43_rom[stage1_mag > 14'd8206 ? 14'd8206 : stage1_mag];
            stage2_frac <= stage1_exponent[1:0];
            stage2_int_exp <= stage1_exponent >>> 2;
            stage2_sign <= stage1_sign;
            stage2_gci <= stage1_gci;
            stage2_index <= stage1_index;
        end

        // Stage 2 -> 3: the multiply.
        stage3_valid <= stage2_valid;
        if (stage2_valid) begin
            stage3_product <= $signed({1'b0, stage2_m43}) * $signed({1'b0, frac_exp_rom[stage2_frac]});
            stage3_int_exp <= stage2_int_exp;
            stage3_sign <= stage2_sign;
            stage3_gci <= stage2_gci;
            stage3_index <= stage2_index;
        end

        // Stage 3 -> output: shift by the exponent's integer part, round on
        // right shifts, apply sign.
        out_valid <= stage3_valid;
        if (stage3_valid) begin
            if (stage3_int_exp >= 0) begin
                shifted = stage3_product <<< stage3_int_exp;
            end else begin
                if (-stage3_int_exp >= 48) shifted = 0;
                else begin
                    rounded = stage3_product + (64'sd1 <<< (-stage3_int_exp - 1));
                    shifted = rounded >>> (-stage3_int_exp);
                end
            end
            out_gci <= stage3_gci;
            out_index <= stage3_index;
            out_data <= stage3_sign ? -shifted[31:0] : shifted[31:0];
        end
    end
end

endmodule
