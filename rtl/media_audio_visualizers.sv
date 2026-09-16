// Passthrough stub -- see media_audio_viewport.sv's header comment for why.
// This core always drives select_visualizer=0 (PLAYER_VISUALIZER tied off
// in MiSTer_MP3.sv), so the real module's own mux would always select its
// "scope" path anyway; a plain registered passthrough is simpler and has
// no rendering-cascade dependencies to pull in for a feature this core
// never activates.
module media_audio_visualizers(
    input wire control_clk,
    input wire [1:0] select_visualizer,
    input wire audio_clk, video_clk, audio_active, sample_tick,
    input wire signed [15:0] sample_left, sample_right,
    input wire [23:0] rgb,
    input wire hs, vs, de, layout_de,
    output reg [23:0] rgb_out = 0,
    output reg hs_out = 0, vs_out = 0, de_out = 0
);
always @(posedge video_clk) begin
    rgb_out <= rgb;
    hs_out  <= hs;
    vs_out  <= vs;
    de_out  <= de;
end
endmodule
