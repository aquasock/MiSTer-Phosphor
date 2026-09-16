// Observe ACKed HPS writes to ADV7513. Pointer-only writes and reads do not
// request reconfiguration. Ignore the local master's own exclusive lease.
module hdmi_i2c_write_watch(
 input wire clk,reset,pad_scl,pad_sda,local_grant,
 output reg changed
);
 (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg[2:0] scl_sync,sda_sync;
 reg old_scl,old_sda,active,matched;
 reg[3:0] bits;reg[1:0] phase;reg[7:0] shift;
 wire start_seen=scl_sync[2]&&old_scl&&old_sda&&!sda_sync[2];
 wire stop_seen=scl_sync[2]&&old_scl&&!old_sda&&sda_sync[2];
 always @(posedge clk)begin
  if(reset)begin
   scl_sync<=0;sda_sync<=0;old_scl<=0;old_sda<=0;active<=0;matched<=0;
   bits<=0;phase<=0;shift<=0;changed<=0;
  end else begin
   scl_sync<={scl_sync[1:0],pad_scl};sda_sync<={sda_sync[1:0],pad_sda};
   old_scl<=scl_sync[2];old_sda<=sda_sync[2];changed<=0;
   if(local_grant||stop_seen)begin active<=0;matched<=0;bits<=0;end
   else if(start_seen)begin active<=1;matched<=0;bits<=0;phase<=0;shift<=0;end
   else if(active&&scl_sync[2]&&!old_scl)begin
    if(bits<8)begin shift<={shift[6:0],sda_sync[2]};bits<=bits+1'b1;end
    else begin
     bits<=0;
     if(sda_sync[2])begin active<=0;matched<=0;end
     else case(phase)
      0:begin matched<=shift==8'h72;phase<=1;end
      1:phase<=2;
      default:if(matched)changed<=1;
     endcase
    end
   end
  end
 end
endmodule
