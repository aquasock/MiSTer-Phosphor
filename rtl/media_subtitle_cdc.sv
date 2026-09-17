// Backpressured command transfer using the same audited snapshot mailboxes as
// player state. Source changes one command only after its applied-toggle echo.
module media_subtitle_cdc(
 input wire control_clk,video_clk,input wire [34:0] command,
 output wire command_ack,
 output reg text_we=0,output reg [7:0] text_addr=0,text_data=0,
 output reg commit=0,output reg [15:0] epoch=0,
 output reg visible=0,output reg [6:0] length0=0,length1=0
);
wire [34:0] received;
reg applied=0;
video_config_cdc #(.WIDTH(35)) subtitle_command_config(
 .src_clk(control_clk),.dst_clk(video_clk),.src_data(command),.dst_data(received));
video_config_cdc #(.WIDTH(1)) subtitle_ack_config(
 .src_clk(video_clk),.dst_clk(control_clk),.src_data(applied),.dst_data(command_ack));
always @(posedge video_clk)begin
 text_we<=0;commit<=0;
 if(received[34]!=applied)begin
  applied<=received[34];
  if(received[17:16]==0)begin text_we<=1;text_addr<=received[15:8];text_data<=received[7:0];end
  else if(received[17:16]==1)begin
   epoch<=received[33:18];length1<=received[14:8];length0<=received[6:0];visible<=received[7];commit<=1;
  end
 end
end
endmodule
