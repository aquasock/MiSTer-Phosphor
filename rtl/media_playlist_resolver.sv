// Resolves M3U filename order against audio members found anywhere in a TAR.
// Dual independent filename fingerprints (FNV-1a plus length) make accidental
// mismatches impractical without storing the filename strings themselves.
module media_playlist_resolver(
 input wire clk,reset,
 input wire audio_write,input wire[7:0] audio_address,input wire[31:0] audio_hash,
 input wire[6:0] audio_length,input wire[2:0] audio_kind,
 input wire[40:0] audio_offset,audio_size,input wire[7:0] audio_count,
 input wire m3u_write,input wire[7:0] m3u_address,input wire[31:0] m3u_hash,
 input wire[6:0] m3u_length,input wire[7:0] m3u_count,input wire start,
 output reg playlist_write=0,output reg[7:0] playlist_address=0,
 output reg[2:0] playlist_kind=0,output reg[40:0] playlist_offset=0,playlist_size=0,
 output reg done=0,ready=0,error=0
);
 (* ramstyle="M10K" *) reg[38:0] names[0:255];
 (* ramstyle="M10K" *) reg[123:0] audio[0:255];
 reg[7:0] name_addr=0,audio_addr=0;reg[38:0] name_q=0;reg[123:0] audio_q=0;
 reg[38:0] wanted=0;reg[2:0] state=0;
 always @(posedge clk)begin
  if(m3u_write)names[m3u_address]<={m3u_length,m3u_hash};
  if(audio_write)audio[audio_address]<={audio_length,audio_hash,audio_kind,audio_offset,audio_size};
  name_q<=names[name_addr];audio_q<=audio[audio_addr];
  playlist_write<=0;
  if(reset)begin
   name_addr<=0;audio_addr<=0;wanted<=0;state<=0;done<=0;ready<=0;error<=0;
  end else case(state)
   0:if(start)begin
      done<=0;ready<=0;error<=m3u_count==0||audio_count==0;
      name_addr<=0;state<=m3u_count==0||audio_count==0?7:1;
     end
   1:state<=2;
   2:begin wanted<=name_q;audio_addr<=0;state<=3;end
   3:state<=4;
   4:if(audio_q[123:85]==wanted)begin
      playlist_write<=1;playlist_address<=name_addr;
      playlist_kind<=audio_q[84:82];playlist_offset<=audio_q[81:41];playlist_size<=audio_q[40:0];
      if(name_addr+1'b1==m3u_count)begin ready<=1;done<=1;state<=0;end
      else begin name_addr<=name_addr+1'b1;state<=1;end
     end else if(audio_addr+1'b1==audio_count)begin error<=1;done<=1;state<=0;end
     else begin audio_addr<=audio_addr+1'b1;state<=3;end
   7:begin done<=1;state<=0;end
   default:state<=0;
  endcase
 end
endmodule
