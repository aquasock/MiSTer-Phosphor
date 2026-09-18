`timescale 1ns/1ps
module vorbis_stream_decoder_tb #(
 parameter integer TARGET_SAMPLES=4096,
 parameter integer DUMP_PCM=0,
 parameter integer DUMP_SPECTRUM=0,
 parameter integer DUMP_RESIDUE=0,
 parameter integer DUMP_IMDCT=0
);
 reg clk=0,reset=1,byte_valid=0;reg [7:0] byte_data=0;always #5 clk=~clk;
 wire byte_ready,pcm_valid,ready,error;wire signed [31:0] pcm_left,pcm_right;wire [31:0] sample_rate;
 integer fd,value,pcm_count=0,dump_fd=0,spectrum_fd=0,residue_fd=0,imdct_fd=0;
 integer cycles=0,first_pcm_cycle=0,last_pcm_cycle=0,max_pcm_gap=0;
 integer phase_cycles[0:15];integer packet_cycles=0,max_packet_cycles=0,packets=0,profile_i;
 integer vector_divisors[0:255];integer vector_divisions=0;
 integer prefix_hits=0,prefix_misses=0,fallback_cycles=0,huffman_requests=0;
 reg [31:0] hash=32'h811c9dc5;
 vorbis_stream_decoder dut(.*,.pcm_ready(1'b1));
 always @(posedge clk)begin
  cycles<=cycles+1;
  phase_cycles[dut.decoder.phase]<=phase_cycles[dut.decoder.phase]+1;
  if(dut.decoder.residues.executor.vector.state==3 &&
     dut.decoder.residues.executor.vector.divider_ready)begin
   vector_divisions<=vector_divisions+1;
   if(dut.decoder.residues.executor.vector.codebook_multiplicand_count<256)
    vector_divisors[dut.decoder.residues.executor.vector.codebook_multiplicand_count]<=
     vector_divisors[dut.decoder.residues.executor.vector.codebook_multiplicand_count]+1;
  end
  if(dut.decoder.residues.executor.huffman.state==0&&
     dut.decoder.residues.executor.huffman.request_valid)huffman_requests<=huffman_requests+1;
  if(dut.decoder.residues.executor.huffman.state==2&&
     dut.decoder.residues.executor.huffman.prefix_result_valid)begin
   if(dut.decoder.residues.executor.huffman.prefix_hit)prefix_hits<=prefix_hits+1;
   else prefix_misses<=prefix_misses+1;
  end
  if(dut.decoder.residues.executor.huffman.state==4)fallback_cycles<=fallback_cycles+1;
  if(dut.decoder.busy)packet_cycles<=packet_cycles+1;
  if(DUMP_SPECTRUM&&dut.decoder.synthesis.workspace_read_data_valid)
   $fdisplay(spectrum_fd,"%0d %0d %0d %0d",packets,dut.decoder.synthesis.channel,
    dut.decoder.synthesis.spectrum_index,dut.decoder.synthesis.workspace_read_data);
  // Capture each channel's residue at the first (highest-numbered) inverse
  // coupling step, before coupling has modified either workspace value.
  if(DUMP_RESIDUE&&dut.decoder.phase==5&&dut.decoder.workspace_read_data_valid&&
     dut.decoder.coupling.coupling_query==dut.decoder.mapping_query_coupling_steps-1'b1)begin
   if(dut.decoder.coupling.state==2)
    $fdisplay(residue_fd,"%0d %0d %0d %0d",packets,
     dut.decoder.coupling_read_address[0],dut.decoder.coupling_read_address>>1,
     dut.decoder.workspace_read_data);
   else if(dut.decoder.coupling.state==4)
    $fdisplay(residue_fd,"%0d %0d %0d %0d",packets,
     dut.decoder.coupling_read_address[0],dut.decoder.coupling_read_address>>1,
     dut.decoder.workspace_read_data);
  end
  if(DUMP_IMDCT&&dut.decoder.synthesis.imdct_sample_valid&&
     dut.decoder.synthesis.imdct_sample_ready)
   $fdisplay(imdct_fd,"%0d %0d %0d %0d",packets,dut.decoder.synthesis.channel,
    dut.decoder.synthesis.imdct_sample_index,dut.decoder.synthesis.imdct_sample_value);
  if(DUMP_RESIDUE&&packets==0&&dut.decoder.residues.executor.vector.start)
   $display("VECTOR book=%0d entry=%0d dims=%0d type=%0d min=%08x delta=%08x mults=%0d",
    dut.decoder.residues.executor.vector.book,dut.decoder.residues.executor.vector.entry,
    dut.decoder.residues.executor.vector.codebook_dimensions,
    dut.decoder.residues.executor.vector.codebook_lookup_type,
    dut.decoder.residues.executor.vector.codebook_minimum,
    dut.decoder.residues.executor.vector.codebook_delta,
    dut.decoder.residues.executor.vector.codebook_multiplicand_count);
  if(dut.decoder.packet_done)begin
   if(packet_cycles>max_packet_cycles)max_packet_cycles<=packet_cycles;
   packet_cycles<=0;packets<=packets+1;
  end
  if(pcm_valid)begin
   if(!pcm_count)first_pcm_cycle<=cycles;
   else if(cycles-last_pcm_cycle>max_pcm_gap)max_pcm_gap<=cycles-last_pcm_cycle;
   last_pcm_cycle<=cycles;
   if(DUMP_PCM)$fdisplay(dump_fd,"%0d %0d",pcm_left,pcm_right);
   pcm_count<=pcm_count+1;hash<=((hash^pcm_left)*32'h01000193)^pcm_right;
  end
 end
 initial begin
  for(profile_i=0;profile_i<16;profile_i=profile_i+1)phase_cycles[profile_i]=0;
  for(profile_i=0;profile_i<256;profile_i=profile_i+1)vector_divisors[profile_i]=0;
  if(DUMP_PCM)dump_fd=$fopen("/tmp/vorbis_fpga_pcm.txt","w");
  if(DUMP_SPECTRUM)spectrum_fd=$fopen("/tmp/vorbis_fpga_spectrum.txt","w");
  if(DUMP_RESIDUE)residue_fd=$fopen("/tmp/vorbis_fpga_residue.txt","w");
  if(DUMP_IMDCT)imdct_fd=$fopen("/tmp/vorbis_fpga_imdct.txt","w");
  repeat(4)@(posedge clk);reset=0;
  fd=$fopen("/tmp/mister_mp3_vorbis_test.ogg","rb");if(!fd)$fatal(1,"fixture open failed");
  while(!$feof(fd)&&pcm_count<TARGET_SAMPLES)begin
   value=$fgetc(fd);if(value>=0)begin @(negedge clk);byte_data=value;byte_valid=1;while(!byte_ready)@(negedge clk);end
  end
  @(negedge clk);byte_valid=0;$fclose(fd);repeat(20)@(posedge clk);
  if(error||!ready||sample_rate!=44100||pcm_count<TARGET_SAMPLES)$fatal(1,"stream decode failed ready=%b error=%b rate=%0d pcm=%0d",ready,error,sample_rate,pcm_count);
  if(DUMP_PCM)$fclose(dump_fd);
  if(DUMP_SPECTRUM)$fclose(spectrum_fd);
  if(DUMP_RESIDUE)$fclose(residue_fd);
  if(DUMP_IMDCT)$fclose(imdct_fd);
  $display("PASS streaming wrapper rate=%0d pcm=%0d hash=%x cycles=%0d active_cycles=%0d cycles_per_sample=%0f max_gap=%0d",
   sample_rate,pcm_count,hash,cycles,last_pcm_cycle-first_pcm_cycle,
   (last_pcm_cycle-first_pcm_cycle)*1.0/(pcm_count-1),max_pcm_gap);
  $display("PROFILE packets=%0d max_packet_cycles=%0d",packets,max_packet_cycles);
  for(profile_i=0;profile_i<16;profile_i=profile_i+1)
   if(phase_cycles[profile_i])$display("PROFILE phase=%0d cycles=%0d",profile_i,phase_cycles[profile_i]);
  $display("PROFILE vector_divisions=%0d",vector_divisions);
  $display("PROFILE huffman_requests=%0d prefix_hits=%0d prefix_misses=%0d fallback_cycles=%0d",
   huffman_requests,prefix_hits,prefix_misses,fallback_cycles);
  for(profile_i=0;profile_i<256;profile_i=profile_i+1)
   if(vector_divisors[profile_i])$display("PROFILE divisor=%0d count=%0d",profile_i,vector_divisors[profile_i]);
  $finish;
 end
 initial begin repeat(50000000)@(posedge clk);$fatal(1,"timeout ready=%b error=%b pcm=%0d",ready,error,pcm_count);end
endmodule
