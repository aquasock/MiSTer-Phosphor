// Codec-independent playback-session classifier and capability registry.
//
// A mounted file begins as a standalone session once format sniffing has
// completed.  A FLAC session may subsequently upgrade to an indexed CUE
// album when its metadata parser publishes a usable seek table.  The future
// mixed-format container gets a distinct mode from the outset.  Keeping this
// policy in one module prevents keyboard, transport, UI and audio routing
// from independently guessing what kind of session is active.
module media_session_control(
 input  wire       clk,
 input  wire       reset,
 input  wire       new_file,
 input  wire       file_mounted,
 input  wire       format_ready,
 input  wire       flac_selected,
 input  wire       flac_album_ready,
 input  wire       single_seek_ready,
 input  wire       container_selected,
 input  wire       container_ready,
 input  wire       container_seek_ready,
 output reg  [1:0] mode=0,
 output reg        mode_changed=0,
 output wire       active,
 output wire       single_file,
 output wire       playlist,
 output wire       full_ui,
 output wire       transport_loaded,
 output wire       can_pause,
 output wire       can_seek,
 output wire       can_next_previous
);
 localparam MODE_NONE=2'd0, MODE_SINGLE=2'd1,
            MODE_FLAC_ALBUM=2'd2, MODE_CONTAINER=2'd3;

 wire [1:0] requested_mode = !file_mounted || !format_ready ? MODE_NONE :
                             container_selected && container_ready ? MODE_CONTAINER :
                             flac_selected && flac_album_ready ? MODE_FLAC_ALBUM :
                             MODE_SINGLE;

 always @(posedge clk) begin
  mode_changed<=0;
  if(reset||new_file)begin
   mode<=MODE_NONE;
   mode_changed<=mode!=MODE_NONE;
  end else if(mode!=requested_mode)begin
   mode<=requested_mode;
   mode_changed<=1;
  end
 end

 assign active=mode!=MODE_NONE;
 assign single_file=mode==MODE_SINGLE;
 assign playlist=mode==MODE_FLAC_ALBUM||mode==MODE_CONTAINER;
 assign full_ui=playlist;
 assign transport_loaded=mode==MODE_FLAC_ALBUM ||
                         (mode==MODE_CONTAINER&&container_ready);
 assign can_pause=active;
 assign can_seek=(mode==MODE_SINGLE&&single_seek_ready) ||
                 mode==MODE_FLAC_ALBUM ||
                 (mode==MODE_CONTAINER&&container_seek_ready);
 assign can_next_previous=playlist;
endmodule
