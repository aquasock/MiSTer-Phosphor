// Post-filter, pre-menu integration. Decoder and transport have no dependency
// on renderer readiness. Only a coalescing presentation-state snapshot crosses.
module media_player_overlay(
 input wire control_clk,video_clk,input wire [90:0] control_state,
 input wire [34:0] subtitle_command,output wire subtitle_ack,
 input wire [23:0] rgb,input wire hs,vs,de,
 input wire layout_de,
 output wire [23:0] rgb_out,output wire hs_out,vs_out,de_out
);
// Only scene construction advances every fourth pixel clock. Pixel lookup,
// RAM publication and timing measurement continue on every clock. SDC applies
// multicycle timing exclusively between these same-enable formatter registers.
(* preserve *) reg [1:0] scene_phase=0;
always @(posedge video_clk) scene_phase<=scene_phase+1'b1;
wire scene_ce=scene_phase==0;
wire [90:0] state_hdmi;
video_config_cdc #(.WIDTH(91)) player_ui_config(
 .src_clk(control_clk),.dst_clk(video_clk),.src_data(control_state),.dst_data(state_hdmi));
wire text_we,object_we,commit,pending,acknowledged;
wire [8:0] text_addr;
wire [7:0] text_data;
wire [3:0] object_addr,scale;
wire [55:0] object_data;
wire [15:0] epoch;
wire [1:0] groups;
wire [11:0] width,height;
wire subtitle_text_we,subtitle_commit,subtitle_visible;
wire [7:0] subtitle_text_addr,subtitle_text_data;
wire [15:0] subtitle_epoch;
wire [6:0] subtitle_length0,subtitle_length1;
media_subtitle_cdc subtitles(.control_clk(control_clk),.video_clk(video_clk),
 .command(subtitle_command),.command_ack(subtitle_ack),
 .text_we(subtitle_text_we),.text_addr(subtitle_text_addr),.text_data(subtitle_text_data),
 .commit(subtitle_commit),.epoch(subtitle_epoch),.visible(subtitle_visible),
 .length0(subtitle_length0),.length1(subtitle_length1));
media_ui_scene scene(
 .clk(video_clk),.ce(scene_ce),.state_in(state_hdmi),.width(width),.height(height),.pending(pending),.acknowledged(acknowledged),
 .text_we(text_we),.text_addr(text_addr),.text_data(text_data),
 .object_we(object_we),.object_addr(object_addr),.object_data(object_data),
 .commit(commit),.commit_epoch(epoch),.commit_groups(groups),.commit_scale(scale),
 .aux_text_we(subtitle_text_we),.aux_text_addr(subtitle_text_addr),.aux_text_data(subtitle_text_data),
 .aux_object_we(1'b0),.aux_object_addr(2'd0),.aux_object_data(56'd0),
 .aux_commit(subtitle_commit),.aux_epoch(subtitle_epoch),.aux_visible(subtitle_visible),
 .aux_auto_layout(1'b1),.aux_length0(subtitle_length0),.aux_length1(subtitle_length1));
media_overlay_compositor compositor(
 .clk(video_clk),.rgb(rgb),.hs(hs),.vs(vs),.de(de),.layout_de(layout_de),.current_epoch(state_hdmi[90:75]),
 .text_we(text_we),.text_addr(text_addr),.text_data(text_data),
 .object_we(object_we),.object_addr(object_addr),.object_data(object_data),
 .commit(commit),.commit_epoch(epoch),.commit_groups(groups),.commit_scale(scale),
 .pending(pending),.acknowledged(acknowledged),.width(width),.height(height),
 .rgb_out(rgb_out),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out));
endmodule
