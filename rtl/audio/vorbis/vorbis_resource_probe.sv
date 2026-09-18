// Resource/throughput feasibility probe for a bounded stereo Vorbis decoder.
// This is intentionally not connected to the media path yet. It models the
// hardware that dominates a real implementation: setup/codebook storage,
// residue working storage, and a four-lane radix-2 transform engine suitable
// for the 2048-sample long-block IMDCT. Keeping the memories writable and the
// arithmetic live prevents Quartus from reducing the estimate to ROMs/wires.
module vorbis_resource_probe(
 input wire clk,input wire reset,output wire [31:0] activity
);
 reg [31:0] lfsr=32'h1aceb00c;
 always @(posedge clk) begin
  if(reset)lfsr<=32'h1aceb00c;
  else lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
 end

 // Bounded unpacked canonical-codebook cache: 8192 entries. A production
 // controller fills it from Vorbis setup packets, then performs one lookup
 // per cycle while walking floor/residue vectors.
 (* ramstyle="M10K" *) reg [31:0] codebook[0:8191];
 reg [12:0] code_wr=0,code_rd=0;
 reg [31:0] code_q=0;
 always @(posedge clk) begin
  if(lfsr[3:0]==0)codebook[code_wr]<={lfsr[15:0],code_wr,3'b0};
  code_q<=codebook[code_rd];
  code_rd<=code_rd+13'd29;
  if(lfsr[3:0]==0)code_wr<=code_wr+1'b1;
 end

 // Stereo residue/floor scratch. The read/modify/write pattern represents
 // vector codebook accumulation; one 24-bit value is retired each cycle.
 (* ramstyle="M10K" *) reg signed [23:0] residue[0:4095];
 (* ramstyle="M10K" *) reg [15:0] floor_curve[0:255];
 reg [11:0] residue_addr=0;
 reg [7:0] floor_addr=0;
 reg signed [23:0] residue_q=0;
 reg [15:0] floor_q=0;
 wire signed [24:0] residue_sum=$signed(residue_q)+$signed({{9{code_q[15]}},code_q[15:0]});
 always @(posedge clk) begin
  residue_q<=residue[residue_addr];
  floor_q<=floor_curve[floor_addr];
  residue[residue_addr]<=residue_sum[23:0];
  if(lfsr[5:0]==0)floor_curve[floor_addr]<=lfsr[15:0];
  residue_addr<=residue_addr+1'b1;
  floor_addr<=floor_addr+1'b1;
 end

 wire [31:0] lane_activity[0:3];
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:lanes
  vorbis_fft_lane_probe #(.SEED(32'h10203040+lane*32'h11111111)) fft_lane(
   .clk(clk),.reset(reset),.stimulus(lfsr^{code_q[15:0],floor_q}),.activity(lane_activity[lane]));
 end endgenerate
 assign activity=code_q^{8'd0,residue_q}^{16'd0,floor_q}^
  lane_activity[0]^lane_activity[1]^lane_activity[2]^lane_activity[3];
endmodule

// One quarter of a 2048-point complex FFT/IMDCT workspace and butterfly.
// Four instances process four butterflies per clock. The three-multiply
// complex product is the intended production topology (12 DSP multiplies
// total), followed by overlap-friendly 24-bit writeback storage.
module vorbis_fft_lane_probe #(
 parameter [31:0] SEED=32'h12345678
)(input wire clk,input wire reset,input wire [31:0] stimulus,output wire [31:0] activity);
 // Separate A/B banks give every RAM one read and one write port. A real FFT
 // stage swaps bank roles between passes; this probe continuously exercises
 // the same legal dual-port topology without creating LUT-expanded RAM.
 (* ramstyle="M10K" *) reg signed [23:0] real_a[0:511];
 (* ramstyle="M10K" *) reg signed [23:0] imag_a[0:511];
 (* ramstyle="M10K" *) reg signed [23:0] real_b[0:511];
 (* ramstyle="M10K" *) reg signed [23:0] imag_b[0:511];
 reg [8:0] address=0;
 reg signed [23:0] ar=0,ai=0,br=0,bi=0;
 reg signed [17:0] wr=0,wi=0;
 reg signed [41:0] p0=0,p1=0,p2=0;
 wire signed [24:0] sum_b=$signed(br)+$signed(bi);
 wire signed [18:0] sum_w=$signed(wr)+$signed(wi);
 wire signed [42:0] rot_r=$signed(p0)-$signed(p1);
 wire signed [43:0] rot_i=$signed(p2)-$signed(p0)-$signed(p1);
 wire signed [23:0] next_r=$signed(ar)+$signed(rot_r[39:16]);
 wire signed [23:0] next_i=$signed(ai)+$signed(rot_i[39:16]);
 always @(posedge clk) begin
  if(reset)begin address<=SEED[8:0];wr<=SEED[17:0];wi<=SEED[25:8];end
  else begin
   ar<=real_a[address];ai<=imag_a[address];
   br<=real_b[address];bi<=imag_b[address];
   // Three real products implement (br+j*bi)*(wr+j*wi).
   p0<=$signed(br)*$signed(wr);
   p1<=$signed(bi)*$signed(wi);
   p2<=$signed(sum_b)*$signed(sum_w);
   real_a[address]<=next_r;
   imag_a[address]<=next_i;
   real_b[address]<=next_r-$signed(stimulus[23:0]);
   imag_b[address]<=next_i+$signed(stimulus[23:0]);
   address<=address+1'b1;
   wr<={wr[16:0],wr[17]^stimulus[0]};
   wi<={wi[16:0],wi[17]^stimulus[1]};
  end
 end
 assign activity={next_r[23:8],next_i[23:8]};
endmodule
