// Passthrough stub. sys/sys_top.v (copied from the sibling MiSTer-Phosphor
// project, see MiSTer_MP3.sv's header comment) instantiates this as part of
// Phosphor's own audio-visualizer OSD feature; this standalone core doesn't
// have or need visualizers, and always drives `enabled` low (via its own
// PLAYER_VISUALIZER/PLAYER_UI_STATE tie-offs upstream of this module in
// sys_top.v), so a plain one-cycle registered passthrough is behaviorally
// identical to the real module for every input this core ever presents --
// simpler and lower-risk than importing Phosphor's real rendering cascade
// for a feature that would stay permanently disabled here regardless.
module media_audio_viewport(
    input wire clk, enabled,
    input wire [47:0] bounds,
    input wire [23:0] rgb,
    input wire hs, vs, de,
    output reg [23:0] rgb_out = 0,
    output reg hs_out = 0, vs_out = 0, de_out = 0, layout_de = 0
);
always @(posedge clk) begin
    rgb_out <= rgb;
    hs_out  <= hs;
    vs_out  <= vs;
    de_out  <= de;
    layout_de <= de;
end
endmodule
