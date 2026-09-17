`timescale 1ns/1ps

module flac_album_control_tb;
parameter HEX_FILE = "/tmp/flac_album.hex";
parameter integer FILE_BYTES = 1;

reg clk = 0;
always #5 clk = ~clk;
reg reset = 1, new_file = 0, enabled = 1, osd_open = 0;
reg [10:0] key = 0;
reg byte_valid = 0;
reg [7:0] byte_data = 0;
reg [35:0] position = 0;
reg reader_start = 0, landed = 0;
wire restart, busy, resume_frame, available, seek_available;
wire [40:0] start_offset;
wire [35:0] start_sample, target_sample, total_samples;
wire [15:0] min_block, max_block;
wire [6:0] current_track_number;
wire current_track_valid;

reg [7:0] bytes [0:FILE_BYTES-1];
integer index = 0;
integer cycles = 0;
initial $readmemh(HEX_FILE, bytes);

flac_album_control dut(
 .clk(clk),.reset(reset),.new_file(new_file),.enabled(enabled),.osd_open(osd_open),.key(key),
 .byte_valid(byte_valid),.byte_data(byte_data),.position(position),.file_size({32'd0,FILE_BYTES[31:0]}),
 .reader_start(reader_start),.landed(landed),.seek_request(1'b0),.seek_target_q(35'd0),
 .restart(restart),.busy(busy),.resume_frame(resume_frame),.start_offset(start_offset),
 .start_sample(start_sample),.target_sample(target_sample),.total_samples(total_samples),
 .min_block(min_block),.max_block(max_block),.tag(),.available(available),.seek_available(seek_available),
 .current_track_valid(current_track_valid),.track_changed(),.current_track_number(current_track_number),
 .current_track_start(),.current_track_end()
);

always @(posedge clk) begin
 cycles <= cycles + 1;
 if (cycles > FILE_BYTES + 20000) begin $display("FAIL timeout"); $finish_and_return(1); end
 if (!reset && index < FILE_BYTES && !available) begin
  byte_valid <= 1;
  byte_data <= bytes[index];
  index <= index + 1;
 end else byte_valid <= 0;
end

task key_event(input pressed, input [8:0] scan);
begin
 @(negedge clk); key <= {~key[10],pressed,scan};
 @(negedge clk);
end
endtask

task finish_seek;
begin
 @(negedge clk); reader_start <= 1;
 @(negedge clk); reader_start <= 0;
 repeat (3) @(negedge clk);
 landed <= 1;
 @(negedge clk); landed <= 0;
 wait (!busy);
end
endtask

initial begin
 repeat (4) @(negedge clk);
 reset <= 0; new_file <= 1;
 @(negedge clk); new_file <= 0;
 wait (available && seek_available);
 if (total_samples != 88200 || min_block != 4096 || max_block != 4096) begin
  $display("FAIL metadata total=%0d min=%0d max=%0d", total_samples,min_block,max_block);
  $finish_and_return(1);
 end
 repeat (8) @(negedge clk);
 if (!current_track_valid || current_track_number != 1) begin
  $display("FAIL initial track valid=%0d number=%0d",current_track_valid,current_track_number);
  $finish_and_return(1);
 end
 key_event(1'b1,9'h031); // N: next track
 wait (restart);
 if (!resume_frame || target_sample != 44100 || start_sample > target_sample || start_offset == 0) begin
  $display("FAIL next target=%0d start=%0d offset=%0d resume=%0d",target_sample,start_sample,start_offset,resume_frame);
  $finish_and_return(1);
 end
 finish_seek();
 key_event(1'b0,9'h031);
 position <= 44100;
 repeat (8) @(negedge clk);
 key_event(1'b1,9'h04d); // P: previous track
 wait (restart);
 if (target_sample != 0 || start_sample != 0) begin
  $display("FAIL previous target=%0d start=%0d",target_sample,start_sample);
  $finish_and_return(1);
 end
 $display("PASS total=%0d next_offset=%0d",total_samples,start_offset);
 $finish;
end
endmodule
