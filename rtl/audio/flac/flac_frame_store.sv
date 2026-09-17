// Two external DDR frame banks. One 64-bit word holds two signed 17-bit
// coded channels in separate 32-bit lanes. Byte enables avoid read/modify/write.
// BASE uses 64-bit word addresses; reserve 131072 words exclusively for music.
// reset requires the memory port reset too. cancel drains held commands/reads.
module flac_frame_store #(
 parameter [28:0] BASE=29'h06080000
)(
 input wire clk,reset,cancel,start,
 output wire start_ready,quiescent,
 input wire begin_valid,
 output wire begin_ready,
 input wire [15:0] frame_size,
 input wire [3:0] channel_assignment,
 input wire sample_valid,sample_channel,
 input wire [15:0] sample_index,
 input wire signed[16:0] sample_data,
 output wire sample_ready,
 input wire commit_valid,
 output wire commit_ready,
 input wire input_finished,
 output wire pcm_valid,
 input wire pcm_ready,
 output wire pcm_eof,
 output wire signed[15:0] pcm_left,pcm_right,
 output reg error,
 output reg [28:0] mem_addr,
 output reg [63:0] mem_data,
 output reg [7:0] mem_be,
 output wire mem_read,mem_write,
 input wire mem_busy,
 input wire [63:0] mem_q,
 input wire mem_q_valid
);
 localparam IDLE=0,WRITE=1,READ=2,WAIT_READ=3;
 reg[1:0] state,full;
 reg active,writing,write_bank,read_bank;
 reg[15:0] sizes[0:1];reg[3:0] assignments[0:1];
 reg[15:0] expected_index,read_index;
 reg expected_channel,samples_complete;
 reg token_valid,token_eof;
 reg signed[15:0] token_left,token_right;
 wire running=active&&!cancel&&!reset&&!error;
 wire want_read=running&&full[read_bank]&&!token_valid;
 assign quiescent=!active&&state==IDLE;
 assign start_ready=quiescent&&!reset&&!cancel;
 assign begin_ready=running&&!writing&&!full[write_bank]&&!input_finished;
 assign sample_ready=running&&writing&&!samples_complete&&state==IDLE&&!want_read;
 assign commit_ready=running&&writing&&samples_complete&&state==IDLE;
 assign mem_read=state==READ&&!reset;
 assign mem_write=state==WRITE&&!reset;
 assign pcm_valid=token_valid&&running;
 assign pcm_eof=token_eof;
 assign pcm_left=token_left;assign pcm_right=token_right;
 wire signed[15:0] decoded_left,decoded_right;wire stereo_error;
 flac_stereo stereo(.assignment_code(assignments[read_bank]),
  .channel0(mem_q[16:0]),.channel1(mem_q[48:32]),
  .left(decoded_left),.right(decoded_right),.error(stereo_error));
 task automatic capture;
  begin
   state<=IDLE;
   if(running)begin
    if(stereo_error||mem_q[31:17]!={15{mem_q[16]}}||mem_q[63:49]!={15{mem_q[48]}})begin error<=1;active<=0;full<=0;end
    else begin token_valid<=1;token_eof<=0;token_left<=decoded_left;token_right<=decoded_right;end
   end
  end
 endtask
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;active<=0;full<=0;writing<=0;write_bank<=0;read_bank<=0;
   sizes[0]<=0;sizes[1]<=0;assignments[0]<=0;assignments[1]<=0;
   expected_index<=0;expected_channel<=0;samples_complete<=0;read_index<=0;
   token_valid<=0;token_eof<=0;token_left<=0;token_right<=0;error<=0;
   mem_addr<=BASE;mem_data<=0;mem_be<=0;
  end else begin
   // Never withdraw or replace a held request during cancel. Responses to
   // accepted old reads are consumed while inactive, before start_ready.
   case(state)
    WRITE:if(!mem_busy)state<=IDLE;
    READ:if(!mem_busy)begin if(mem_q_valid)capture();else state<=WAIT_READ;end
    WAIT_READ:if(mem_q_valid)capture();
    default:state<=IDLE;
   endcase
   if(cancel)begin
    active<=0;full<=0;writing<=0;token_valid<=0;error<=0;
   end else if(start&&start_ready)begin
    active<=1;full<=0;writing<=0;write_bank<=0;read_bank<=0;
    expected_index<=0;expected_channel<=0;samples_complete<=0;read_index<=0;
    token_valid<=0;token_eof<=0;error<=0;
   end else if(running)begin
    if(begin_valid&&begin_ready)begin
     if(frame_size==0||!(channel_assignment==1||channel_assignment==8||channel_assignment==9||channel_assignment==10))begin error<=1;active<=0;end
     else begin
      writing<=1;sizes[write_bank]<=frame_size;assignments[write_bank]<=channel_assignment;
      expected_index<=0;expected_channel<=0;samples_complete<=0;
     end
    end
    if(state==IDLE&&want_read)begin
     mem_addr<=BASE+{12'd0,read_bank,read_index};mem_be<=8'hff;state<=READ;
    end else if(sample_valid&&sample_ready)begin
     if(sample_channel!=expected_channel||sample_index!=expected_index)begin error<=1;active<=0;full<=0;end
     else begin
      mem_addr<=BASE+{12'd0,write_bank,sample_index};
      mem_data<=sample_channel?{{15{sample_data[16]}},sample_data,32'd0}:{32'd0,{15{sample_data[16]}},sample_data};
      mem_be<=sample_channel?8'hf0:8'h0f;state<=WRITE;
      if(expected_index==sizes[write_bank]-1'b1)begin
       expected_index<=0;expected_channel<=1;if(expected_channel)samples_complete<=1;
      end else expected_index<=expected_index+1'b1;
     end
    end
    if(commit_valid&&commit_ready)begin full[write_bank]<=1;write_bank<=!write_bank;writing<=0;end
    if(pcm_valid&&pcm_ready)begin
     token_valid<=0;
     if(token_eof)active<=0;
     else if(read_index==sizes[read_bank]-1'b1)begin
      full[read_bank]<=0;read_bank<=!read_bank;read_index<=0;
     end else read_index<=read_index+1'b1;
    end
    if(input_finished&&full==0&&!writing&&state==IDLE&&!token_valid)begin
     token_valid<=1;token_eof<=1;token_left<=0;token_right<=0;
    end
   end
  end
 end
endmodule
