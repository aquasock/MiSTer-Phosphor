// Passthrough stub -- see media_audio_viewport.sv's header comment for why.
// This core always drives control_state/subtitle_command as all-zero
// (PLAYER_UI_STATE/PLAYER_SUBTITLE_COMMAND tied off in MiSTer_MP3.sv), so
// the real overlay compositor would never actually draw anything for this
// core anyway; a plain combinational passthrough (zero added latency, no
// registers to keep in sync with) is simpler and has no scene/subtitle/
// compositor sub-module dependencies to pull in for a feature this core
// never activates.
module media_player_overlay(
    input wire control_clk, video_clk,
    input wire [90:0] control_state,
    input wire [34:0] subtitle_command,
    output wire subtitle_ack,
    input wire [23:0] rgb,
    input wire hs, vs, de,
    input wire layout_de,
    output wire [23:0] rgb_out,
    output wire hs_out, vs_out, de_out
);
assign subtitle_ack = 1'b1;
assign rgb_out = rgb;
assign hs_out  = hs;
assign vs_out  = vs;
assign de_out  = de;
endmodule
