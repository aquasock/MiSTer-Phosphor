// One serial divider converts album and track sample counts to 360000 Hz.
// 360000/44100 = 400/49; retain subsecond precision for track-relative seeks.
module media_music_time(
 input wire clk,reset,track_changed,
 input wire[35:0] position,total,track_position,track_total,track_start,
 output reg[34:0] elapsed_q=0,total_q=0,track_elapsed_q=0,track_total_q=0,track_start_q=0,
 output reg track_times_valid=0
);
 reg [2:0] which=0;
 reg [5:0] count=0;
 reg [47:0] quotient=0;
 reg [5:0] remainder=0;
 reg [35:0] sample_count;
 always @* begin
  case(which)
   0:sample_count=position;1:sample_count=total;2:sample_count=track_position;
   3:sample_count=track_total;default:sample_count=track_start;
  endcase
 end
 wire [6:0] trial={remainder,quotient[47]};
 wire [6:0] difference=trial-7'd49;
 // Round durations and track origin upward; origin then maps back to the
 // exact starting sample in the existing floor(q*49/400) seek converter.
 wire round_up=(which==1||which==3||which==4)&&remainder!=0;
 wire [48:0] rounded={1'b0,quotient}+{{48{1'b0}},round_up};
 wire [34:0] result=(|rounded[48:35])?{35{1'b1}}:rounded[34:0];
 always @(posedge clk)begin
  if(reset)begin
   which<=0;count<=0;quotient<=0;remainder<=0;elapsed_q<=0;total_q<=0;
   track_elapsed_q<=0;track_total_q<=0;track_start_q<=0;track_times_valid<=0;
  end else if(track_changed)begin
   which<=0;count<=0;track_times_valid<=0;
  end else if(count==0)begin
   quotient<={12'd0,sample_count}*48'd400;remainder<=0;count<=48;
  end else if(count==49)begin
   case(which)
    0:elapsed_q<=result;1:total_q<=result;2:track_elapsed_q<=result;3:track_total_q<=result;
    4:begin track_start_q<=result;track_times_valid<=1;end
   endcase
   which<=which==4?3'd0:which+1'b1;count<=0;
  end else begin
   remainder<=difference[6]?trial[5:0]:difference[5:0];
   quotient<={quotient[46:0],!difference[6]};
   count<=count==1?6'd49:count-1'b1;
  end
 end
endmodule
