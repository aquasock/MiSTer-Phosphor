// Packet-level phase sequencer. Datapath arbitration follows these mutually
// exclusive phases so the Huffman reader, setup-query ports, residue workspace,
// IMDCT, and PCM path can each be shared rather than duplicated.
module vorbis_audio_sequence(
 input wire clk,input wire reset,input wire packet_start,input wire packet_exhausted,
 output reg floor_start=0,input wire floor_done,
 output reg residue_start=0,input wire residue_ready,input wire residue_done,
 output reg coupling_start=0,input wire coupling_ready,input wire coupling_done,
 output reg floor0_start=0,input wire floor0_ready,input wire floor0_done,
 output reg floor1_start=0,input wire floor1_ready,input wire floor1_done,
 output reg synthesis_start=0,input wire synthesis_ready,input wire synthesis_done,
 output reg finish_packet=0,output wire busy,output reg packet_done=0,
 input wire stage_error,output reg error=0,output wire [3:0] phase
);
 localparam WAIT=0,FLOORS=1,RES_LAUNCH=2,RESIDUE=3,COUPLE_LAUNCH=4,COUPLE=5,
  FLOOR0_LAUNCH=6,FLOOR0=7,FLOOR1_LAUNCH=8,FLOOR1=9,
  SYNTH_LAUNCH=10,SYNTH=11,FINISH=12;
 reg [3:0] state=WAIT;
 assign busy=state!=WAIT;assign phase=state;
 always @(posedge clk)begin
  if(reset)begin state<=WAIT;floor_start<=0;residue_start<=0;coupling_start<=0;
   floor0_start<=0;floor1_start<=0;synthesis_start<=0;finish_packet<=0;packet_done<=0;error<=0;end
  else begin
   floor_start<=0;residue_start<=0;coupling_start<=0;floor0_start<=0;floor1_start<=0;
   synthesis_start<=0;finish_packet<=0;packet_done<=0;
   if(stage_error)error<=1;
   case(state)
    WAIT:if(packet_start)begin error<=0;floor_start<=1;state<=FLOORS;end
    FLOORS:if(floor_done)state<=RES_LAUNCH;else if(packet_exhausted)state<=FINISH;
    RES_LAUNCH:if(residue_ready)begin residue_start<=1;state<=RESIDUE;end
    RESIDUE:if(residue_done)state<=COUPLE_LAUNCH;
    COUPLE_LAUNCH:if(coupling_ready)begin coupling_start<=1;state<=COUPLE;end
    COUPLE:if(coupling_done)state<=FLOOR0_LAUNCH;
    FLOOR0_LAUNCH:if(floor0_ready)begin floor0_start<=1;state<=FLOOR0;end
    FLOOR0:if(floor0_done)state<=FLOOR1_LAUNCH;
    FLOOR1_LAUNCH:if(floor1_ready)begin floor1_start<=1;state<=FLOOR1;end
    FLOOR1:if(floor1_done)state<=SYNTH_LAUNCH;
    SYNTH_LAUNCH:if(synthesis_ready)begin synthesis_start<=1;state<=SYNTH;end
    SYNTH:if(synthesis_done)state<=FINISH;
    FINISH:begin finish_packet<=1;packet_done<=!error;state<=WAIT;end
   endcase
  end
 end
endmodule
