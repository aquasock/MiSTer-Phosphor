// True dual-port synchronous workspace used by the serialized FFT.  Both
// butterfly outputs are committed on one edge, and both inputs are fetched
// together, matching the two physical ports of one M10K bank.
module vorbis_fft_ram #(
 parameter WIDTH=24,parameter DEPTH=2048,parameter ADDR_WIDTH=11
)(
 input wire clk,
 input wire write_a,input wire [ADDR_WIDTH-1:0] address_a,input wire [WIDTH-1:0] data_a,
 output wire [WIDTH-1:0] q_a,
 input wire write_b,input wire [ADDR_WIDTH-1:0] address_b,input wire [WIDTH-1:0] data_b,
 output wire [WIDTH-1:0] q_b
);
`ifdef SYNTHESIS
 wire [WIDTH-1:0] q_a_wire,q_b_wire;
 assign q_a=q_a_wire;assign q_b=q_b_wire;
 altsyncram ram(
  .clock0(clk),.address_a(address_a),.data_a(data_a),.wren_a(write_a),.q_a(q_a_wire),
  .clock1(clk),.address_b(address_b),.data_b(data_b),.wren_b(write_b),.q_b(q_b_wire),
  .aclr0(1'b0),.aclr1(1'b0),.addressstall_a(1'b0),.addressstall_b(1'b0),
  .byteena_a(1'b1),.byteena_b(1'b1),.clocken0(1'b1),.clocken1(1'b1),
  .clocken2(1'b1),.clocken3(1'b1),.eccstatus(),.rden_a(1'b1),.rden_b(1'b1));
 defparam ram.numwords_a=DEPTH,ram.widthad_a=ADDR_WIDTH,ram.width_a=WIDTH,
  ram.numwords_b=DEPTH,ram.widthad_b=ADDR_WIDTH,ram.width_b=WIDTH,
  ram.address_reg_b="CLOCK1",ram.clock_enable_input_a="BYPASS",
  ram.clock_enable_input_b="BYPASS",ram.clock_enable_output_a="BYPASS",
  ram.clock_enable_output_b="BYPASS",ram.indata_reg_b="CLOCK1",
  ram.intended_device_family="Cyclone V",ram.lpm_type="altsyncram",
  ram.operation_mode="BIDIR_DUAL_PORT",ram.outdata_aclr_a="NONE",
  ram.outdata_aclr_b="NONE",ram.outdata_reg_a="UNREGISTERED",
  ram.outdata_reg_b="UNREGISTERED",ram.power_up_uninitialized="FALSE",
  ram.read_during_write_mode_port_a="NEW_DATA_NO_NBE_READ",
  ram.read_during_write_mode_port_b="NEW_DATA_NO_NBE_READ",ram.width_byteena_a=1,
  ram.width_byteena_b=1,ram.wrcontrol_wraddress_reg_b="CLOCK1";
`else
 (* ramstyle="M10K" *) reg [WIDTH-1:0] memory[0:DEPTH-1];
 reg [WIDTH-1:0] q_a_sim,q_b_sim;
 assign q_a=q_a_sim;assign q_b=q_b_sim;
 always @(posedge clk)begin
  if(write_a)memory[address_a]<=data_a;
  q_a_sim<=memory[address_a];
  if(write_b)memory[address_b]<=data_b;
  q_b_sim<=memory[address_b];
 end
`endif
endmodule

// Serialized radix-2 inverse FFT used by the Vorbis IMDCT wrapper. Input is
// loaded in bit-reversed order, output is natural order. Each stage scales by
// one bit, yielding a normalized 1/N transform and bounded 24-bit workspace.
module vorbis_fft(
 input wire clk,input wire reset,
 input wire load_valid,output wire load_ready,input wire [10:0] load_address,
 input wire signed [23:0] load_real,input wire signed [23:0] load_imag,
 input wire start,input wire [3:0] length_log2,
 input wire output_request,input wire [10:0] output_address,
 output reg output_valid=0,output reg signed [23:0] output_real=0,output reg signed [23:0] output_imag=0,
 output wire ready,output reg done=0,output reg error=0
);
 localparam IDLE=0,READ_WAIT=1,COMBINE=2,WRITE_PAIR=3,FINISH=4;
 reg [3:0] state=IDLE,stage=0,saved_log2=0;
 wire signed [23:0] mem_real_a_q,mem_imag_a_q,mem_real_b_q,mem_imag_b_q;
 reg signed [23:0] ar=0,ai=0,br=0,bi=0;
 reg signed [23:0] out_a_r=0,out_a_i=0,out_b_r=0,out_b_i=0;
 reg [10:0] base=0,j=0,a_address=0,b_address=0;
 reg [35:0] twiddle_mem[0:1023];reg [9:0] twiddle_address=0;
 reg signed [17:0] wr=0,wi=0;reg signed [24:0] sum_b=0;reg signed [18:0] sum_w=0;
 reg signed [41:0] p0=0,p1=0;reg signed [43:0] p2=0;
 reg signed [43:0] tr=0,ti=0;
 initial $readmemh("rtl/audio/vorbis/vorbis_fft_twiddle.hex",twiddle_mem);
 assign ready=state==IDLE;
 assign load_ready=state==IDLE&&!start;
 wire load_write=state==IDLE&&load_valid&&load_ready;
 wire pair_write=state==WRITE_PAIR;
 wire [10:0] memory_address_a=state==IDLE?(output_request?output_address:load_address):a_address;
 wire [10:0] memory_address_b=b_address;
 wire [23:0] real_data_a=load_write?load_real:out_a_r;
 wire [23:0] imag_data_a=load_write?load_imag:out_a_i;
 vorbis_fft_ram real_mem(clk,load_write||pair_write,memory_address_a,real_data_a,mem_real_a_q,
  pair_write,memory_address_b,out_b_r,mem_real_b_q);
 vorbis_fft_ram imag_mem(clk,load_write||pair_write,memory_address_a,imag_data_a,mem_imag_a_q,
  pair_write,memory_address_b,out_b_i,mem_imag_b_q);
 reg output_pending=0;
 always @(posedge clk)begin
  output_pending<=output_request&&state==IDLE;output_valid<=output_pending;
  if(output_pending)begin output_real<=mem_real_a_q;output_imag<=mem_imag_a_q;end
 end
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;done<=0;error<=0;stage<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     error<=0;
     if(length_log2<7||length_log2>11)begin error<=1;state<=FINISH;end
     else begin
      saved_log2<=length_log2;stage<=0;base<=0;j<=0;
      a_address<=0;b_address<=1;state<=READ_WAIT;
     end
    end
    READ_WAIT:state<=COMBINE;
    COMBINE:begin
     ar=$signed(mem_real_a_q);ai=$signed(mem_imag_a_q);
     br=$signed(mem_real_b_q);bi=$signed(mem_imag_b_q);
     twiddle_address=j<<(10-stage);
     wr=$signed(twiddle_mem[j<<(10-stage)][35:18]);
     wi=$signed(twiddle_mem[j<<(10-stage)][17:0]);
     sum_b=$signed(br)+$signed(bi);sum_w=$signed(wr)+$signed(wi);
     p0=$signed(br)*$signed(wr);p1=$signed(bi)*$signed(wi);p2=$signed(sum_b)*$signed(sum_w);
     tr=($signed(p0)-$signed(p1))>>>17;ti=($signed(p2)-$signed(p0)-$signed(p1))>>>17;
     out_a_r<=($signed(ar)+$signed(tr))>>>1;out_a_i<=($signed(ai)+$signed(ti))>>>1;
     out_b_r<=($signed(ar)-$signed(tr))>>>1;out_b_i<=($signed(ai)-$signed(ti))>>>1;
     state<=WRITE_PAIR;
    end
    // Both writes commit on this edge while the next pair of synchronous RAM
    // addresses is selected, overlapping loop bookkeeping with the read.
    WRITE_PAIR:begin
     if(j+1'b1<(11'd1<<stage))begin
      j<=j+1'b1;a_address<=base+j+1'b1;
      b_address<=base+j+1'b1+(11'd1<<stage);state<=READ_WAIT;
     end
     // The 2048-point transform needs a 12-bit length sentinel. With an
     // 11-bit left operand, (1 << 11) truncates to zero and each stage would
     // incorrectly stop after only its first butterfly.
     else if({1'b0,base}+(12'd2<<stage)<(12'd1<<saved_log2))begin
      base<=base+(11'd2<<stage);j<=0;
      a_address<=base+(11'd2<<stage);
      b_address<=base+(11'd2<<stage)+(11'd1<<stage);state<=READ_WAIT;
     end
     else if(stage+1'b1<saved_log2)begin
      stage<=stage+1'b1;base<=0;j<=0;a_address<=0;
      b_address<=11'd1<<(stage+1'b1);state<=READ_WAIT;
     end
     else state<=FINISH;
    end
    FINISH:begin done<=!error;state<=IDLE;end
   endcase
  end
 end
endmodule
