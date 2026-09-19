// Controls visibility uses wall time; the cue clock remains presentation time.
// Session changes invalidate all future cue-provider state. Seeking invalidates
// cue selection; a future provider must reselect at the actual landing position.
module media_ui_state #(parameter integer CLOCK_HZ=20000000)(
 input wire clk,reset,new_file,loaded,paused,seeking,
 input wire [34:0] elapsed_q,target_q,duration_q,
 input wire duration_valid,
 input wire music_mode,track_changed,track_valid,album_ui_visible,widescreen,
 input wire [34:0] track_elapsed_q,track_duration_q,track_origin_q,
 output wire album_duration_known,
 output wire [90:0] scene_state
);
reg [15:0] session=0;
reg paused_d=0,seeking_d=0,loaded_d=0;
reg [34:0] target_d=0;
reg [31:0] hide_count=0;
reg album_sequence=0,seek_track_pending=0;
wire manual_activity=paused!=paused_d || seeking!=seeking_d || (seeking && target_q!=target_d);
// The FLAC album duration comes from parsed STREAMINFO and remains authoritative.
// A restart crosses the native sample counter back into clk_sys asynchronously,
// so rapid N/P/seek activity may briefly present an old position beyond the new
// target. That transport transient must not permanently turn the progress bar
// into its hatched "unknown duration" state.
wire known=duration_valid;
assign album_duration_known=known;
// Natural track changes use two three-second pages.  Present the album
// timeline first for orientation, then finish on the newly-current track.
// Explicit seeks remain track-relative for their entire visibility window.
wire track_phase=music_mode&&(seeking||!album_sequence||
                 (hide_count!=0&&hide_count<=CLOCK_HZ*3));
wire [34:0] relative_target=target_q>=track_origin_q?target_q-track_origin_q:35'd0;
wire [34:0] track_preview=relative_target>track_duration_q?track_duration_q:relative_target;
wire display_known=known&&(!track_phase||track_valid||seeking);
wire [34:0] display_duration=track_phase?track_duration_q:duration_q;
wire [34:0] display_elapsed=track_phase?(seeking?track_preview:track_elapsed_q):(seeking?target_q:elapsed_q);
// Bit 72 carries the manually toggled album UI; bit 71 carries the HDMI
// aspect choice so fixed-shape album panels can counter the 4:3-to-16:9 stretch.
assign scene_state={session,loaded,loaded&&(seeking||hide_count!=0),album_ui_visible,widescreen,display_known,
 display_duration,display_elapsed};
always @(posedge clk) begin
 paused_d<=paused;seeking_d<=seeking;loaded_d<=loaded;target_d<=target_q;
 if(reset) begin session<=0;hide_count<=0;album_sequence<=0;seek_track_pending<=0;end
 else if(new_file) begin session<=session+1'b1;hide_count<=0;album_sequence<=0;seek_track_pending<=0;end
 else begin
  if(seeking && (!seeking_d || target_q!=target_d)) session<=session+1'b1;
  // Seek landing republishes track metadata; do not treat it as natural progression.
  if(music_mode&&seeking)seek_track_pending<=1;
  else if(track_valid&&!track_changed)seek_track_pending<=0;
  if(manual_activity||seeking)begin hide_count<=CLOCK_HZ*3;album_sequence<=0;end
  else if((loaded&&!loaded_d || music_mode&&track_changed)&&!seek_track_pending)begin
   hide_count<=music_mode?CLOCK_HZ*6:CLOCK_HZ*3;album_sequence<=music_mode;
  end
  else if(hide_count!=0) hide_count<=hide_count-1'b1;
 end
end
endmodule
