`timescale 1ns/1ps
module vorbis_audio_sequence_tb;
 reg clk=0,reset=1,packet_start=0,packet_exhausted=0,floor_done=0,residue_done=0,coupling_done=0;
 reg floor0_done=0,floor1_done=0,synthesis_done=0,stage_error=0;
 wire floor_start,residue_start,coupling_start,floor0_start,floor1_start,synthesis_start;
 wire finish_packet,busy,packet_done,error;wire [3:0] phase;
 reg residue_ready=0,coupling_ready=0,floor0_ready=0,floor1_ready=0,synthesis_ready=0;
 always #5 clk=~clk;
 vorbis_audio_sequence dut(.*);
 initial begin
  repeat(3)@(negedge clk);reset=0;
  @(negedge clk);packet_start=1;@(negedge clk);packet_start=0;if(!busy||phase!=1)$fatal(1,"floor launch");
  @(negedge clk);floor_done=1;@(negedge clk);floor_done=0;repeat(2)@(negedge clk);if(residue_start)$fatal(1,"residue launched before ready");
  residue_ready=1;@(negedge clk);residue_ready=0;if(!residue_start)$fatal(1,"residue pulse");
  @(negedge clk);residue_done=1;@(negedge clk);residue_done=0;coupling_ready=1;@(negedge clk);coupling_ready=0;if(!coupling_start)$fatal(1,"coupling pulse");
  @(negedge clk);coupling_done=1;@(negedge clk);coupling_done=0;floor0_ready=1;@(negedge clk);floor0_ready=0;if(!floor0_start)$fatal(1,"floor0 pulse");
  @(negedge clk);floor0_done=1;@(negedge clk);floor0_done=0;floor1_ready=1;@(negedge clk);floor1_ready=0;if(!floor1_start)$fatal(1,"floor1 pulse");
  @(negedge clk);floor1_done=1;@(negedge clk);floor1_done=0;synthesis_ready=1;@(negedge clk);synthesis_ready=0;if(!synthesis_start)$fatal(1,"synthesis pulse");
  @(negedge clk);synthesis_done=1;@(negedge clk);synthesis_done=0;@(negedge clk);if(!finish_packet||!packet_done)$fatal(1,"packet finish");
  @(negedge clk);if(busy)$fatal(1,"did not return idle");
  $display("PASS packet floor/residue/coupling/apply/synthesis sequence");$finish;
 end
 initial begin repeat(200)@(posedge clk);$fatal(1,"timeout phase=%0d",phase);end
endmodule
