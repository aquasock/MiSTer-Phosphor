// Coalescing mailbox for slow video configuration. Source holds each snapshot
// until acknowledged; destination samples only after a synchronized request.
// Intermediate settings may coalesce. This is not a streaming-data FIFO.
module video_config_cdc #(parameter WIDTH=1)(
 input wire src_clk,dst_clk,input wire [WIDTH-1:0] src_data,
 output reg [WIDTH-1:0] dst_data=0
);
reg [WIDTH-1:0] held_data=0;
reg request=0,acknowledge=0;
(* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
reg [2:0] req_sync=0,ack_sync=0;
always @(posedge src_clk) begin
 ack_sync <= {ack_sync[1:0],acknowledge};
 if(request==ack_sync[2] && src_data!=held_data) begin
  held_data<=src_data;request<=~request;
 end
end
always @(posedge dst_clk) begin
 req_sync<={req_sync[1:0],request};
 if(req_sync[2]!=acknowledge) begin
  dst_data<=held_data;acknowledge<=req_sync[2];
 end
end
endmodule
