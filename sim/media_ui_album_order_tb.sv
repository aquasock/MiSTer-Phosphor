`timescale 1ns/1ps

module media_ui_album_order_tb;
reg clk=0,reset=1,new_file=0,loaded=0,paused=0,seeking=0;
reg music_mode=1,track_changed=0,track_valid=1;
reg album_ui_visible=0;
reg [34:0] elapsed_q=35'd50,target_q=0,duration_q=35'd100;
reg [34:0] track_elapsed_q=35'd5,track_duration_q=35'd20,track_origin_q=35'd40;
wire known;
wire [90:0] scene;
always #5 clk=~clk;

media_ui_state #(.CLOCK_HZ(10)) dut(
 .clk(clk),.reset(reset),.new_file(new_file),.loaded(loaded),.paused(paused),.seeking(seeking),
 .elapsed_q(elapsed_q),.target_q(target_q),.duration_q(duration_q),.duration_valid(1'b1),
 .music_mode(music_mode),.track_changed(track_changed),.track_valid(track_valid),
 .track_elapsed_q(track_elapsed_q),.track_duration_q(track_duration_q),.track_origin_q(track_origin_q),
 .album_duration_known(known),.scene_state(scene));

task expect_album; begin
 if(!scene[73]||scene[69:35]!=duration_q||scene[34:0]!=elapsed_q)
  $fatal(1,"expected album page duration=%0d elapsed=%0d",scene[69:35],scene[34:0]);
end endtask
task expect_track; begin
 if(!scene[73]||scene[69:35]!=track_duration_q||scene[34:0]!=track_elapsed_q)
  $fatal(1,"expected track page duration=%0d elapsed=%0d",scene[69:35],scene[34:0]);
end endtask

initial begin
 repeat(3)@(negedge clk);reset=0;loaded=1;
 repeat(3)@(negedge clk);expect_album();
 repeat(31)@(negedge clk);expect_track();
 repeat(31)@(negedge clk);if(scene[73])$fatal(1,"sequence did not hide");
 track_changed=1;@(negedge clk);track_changed=0;
 repeat(3)@(negedge clk);expect_album();
 repeat(31)@(negedge clk);expect_track();
 seeking=1;target_q=35'd47;@(negedge clk);repeat(2)@(negedge clk);
 if(scene[69:35]!=track_duration_q||scene[34:0]!=35'd7)$fatal(1,"seek was not track relative");
 seeking=0;elapsed_q=duration_q+35'd360001;
 repeat(3)@(negedge clk);
 if(!known||!scene[70])$fatal(1,"transient position overrun invalidated STREAMINFO duration");
 $display("PASS album-first, track-second, seek-track-relative status order");
 $finish;
end
endmodule
