// Exclusive access gate for the HPS HDMI I2C interface and a local controller.
// No register rewriting is performed here. The local requester must keep both
// drivers released until granted, finish with STOP, and hold request until grant.
// HPS observes a busy (SCL-low) bus while the local controller owns the pins.
// Integration must verify the real HPS controller's bus-busy/timeout behavior.
module hdmi_i2c_owner #(
 parameter integer BUS_FREE_CYCLES=250 // 5 us at 50 MHz
)(
 input wire clk,reset,
 input wire pad_scl,pad_sda,
 input wire hps_scl_low,hps_sda_low,
 output wire hps_scl_in,hps_sda_in,
 input wire local_request,local_done,
 input wire local_scl_low,local_sda_low,
 output reg local_grant,
 output wire drive_scl_low,drive_sda_low
);
 localparam CW=$clog2(BUS_FREE_CYCLES+1);
 (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
 reg [2:0] scl_sync,sda_sync;
 reg old_scl,old_sda,transaction,release_pending;
 reg [CW-1:0] free_count;
 wire start_seen=scl_sync[2]&&old_scl&&old_sda&&!sda_sync[2];
 wire stop_seen=scl_sync[2]&&old_scl&&!old_sda&&sda_sync[2];
 wire bus_free=scl_sync[2]&&sda_sync[2]&&!transaction&&!start_seen;
 assign drive_scl_low=local_grant?local_scl_low:hps_scl_low;
 assign drive_sda_low=local_grant?local_sda_low:hps_sda_low;
 assign hps_scl_in=local_grant?1'b0:pad_scl;
 assign hps_sda_in=local_grant?1'b1:pad_sda;
 always @(posedge clk) begin
  if(reset) begin
   scl_sync<=0;sda_sync<=0;old_scl<=0;old_sda<=0;
   transaction<=0;release_pending<=0;free_count<=0;local_grant<=0;
  end else begin
   scl_sync<={scl_sync[1:0],pad_scl};sda_sync<={sda_sync[1:0],pad_sda};
   old_scl<=scl_sync[2];old_sda<=sda_sync[2];
   if(start_seen)transaction<=1;
   else if(stop_seen)transaction<=0;
   if(bus_free)begin
    if(free_count<CW'(BUS_FREE_CYCLES))free_count<=free_count+1'b1;
   end else free_count<=0;
   if(!local_grant)begin
    release_pending<=0;
    // Direct intent qualification also blocks a new HPS START during the
    // synchronizer latency. Acquisition never interrupts a tracked transfer.
    if(local_request&&free_count==CW'(BUS_FREE_CYCLES)&&
       pad_scl&&pad_sda&&!hps_scl_low&&!hps_sda_low)begin
     local_grant<=1;free_count<=0;
    end
   end else begin
    if(local_done)release_pending<=1;
    if((release_pending||local_done)&&free_count==CW'(BUS_FREE_CYCLES)&&
       pad_scl&&pad_sda&&!local_scl_low&&!local_sda_low)begin
     local_grant<=0;release_pending<=0;free_count<=0;
    end
   end
  end
 end
endmodule
