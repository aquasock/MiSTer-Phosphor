// Single-register I2C transactions. Caller must own the bus before request.
// Read uses write-address/register/repeated-START/read-address/data/NACK/STOP.
// Drivers are open-drain intents. A clock timeout sets error, releases SCL,
// and waits for clock recovery before STOP. Ownership stays local until then.
module i2c_register_master #(
 parameter integer QUARTER_CYCLES=125,
 parameter integer STRETCH_LIMIT=250000
)(
 input wire clk,reset,
 input wire request,read_register,
 input wire[6:0] address,
 input wire[7:0] register_address,write_data,
 output wire ready,
 output reg done,error,
 output reg[7:0] read_data,
 input wire pad_scl,pad_sda,
 output reg scl_low,sda_low
);
 localparam IDLE=0,START=1,LOW=2,RISE=3,HIGH=4,FALL=5,
  RESTART_LOW=6,RESTART_RISE=7,RESTART_START=8,STOP_LOW=9,STOP_RISE=10,STOP_RELEASE=11,FINISH=12,RECOVER=13;
 localparam QW=$clog2(QUARTER_CYCLES+1),TW=$clog2(STRETCH_LIMIT+1);
 reg[3:0] state;reg[QW-1:0] divider;reg[TW-1:0] stretch;
 (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg[2:0] scl_sync,sda_sync;
 reg[6:0] addr;reg[7:0] reg_addr,data,tx;reg rd,receiving;reg[2:0] stage;reg[3:0] bit_number;
 wire tick=divider==0;
 assign ready=state==IDLE&&!reset;
 task automatic send_byte(input[7:0] value,input receive_byte,input[2:0] next_stage);
  begin tx<=value;receiving<=receive_byte;stage<=next_stage;bit_number<=0;state<=LOW;end
 endtask
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;divider<=0;stretch<=0;scl_sync<=0;sda_sync<=0;
   addr<=0;reg_addr<=0;data<=0;tx<=0;rd<=0;receiving<=0;stage<=0;bit_number<=0;
   done<=0;error<=0;read_data<=0;scl_low<=0;sda_low<=0;
  end else begin
   scl_sync<={scl_sync[1:0],pad_scl};sda_sync<={sda_sync[1:0],pad_sda};done<=0;
   if(tick)divider<=QW'(QUARTER_CYCLES-1);else divider<=divider-1'b1;
   if((state==RISE||state==RESTART_RISE||state==STOP_RISE)&&!scl_sync[2])begin
    if(stretch==TW'(STRETCH_LIMIT-1))begin
     state<=RECOVER;scl_low<=0;sda_low<=1;error<=1;stretch<=0;
    end else stretch<=stretch+1'b1;
   end else stretch<=0;
   if(request&&ready)begin
    addr<=address;reg_addr<=register_address;data<=write_data;rd<=read_register;
    error<=0;read_data<=0;state<=START;divider<=QW'(QUARTER_CYCLES-1);scl_low<=0;sda_low<=1;
   end else if(tick)case(state)
    START:begin scl_low<=1;send_byte({addr,1'b0},0,0);end
    LOW:begin scl_low<=1;sda_low<=!receiving&&bit_number<8?!tx[7-bit_number[2:0]]:1'b0;state<=RISE;end
    RISE:begin scl_low<=0;if(!scl_low&&scl_sync[2])state<=HIGH;end
    HIGH:begin
     if(bit_number==8&&!receiving&&sda_sync[2])error<=1;
     if(bit_number<8&&receiving)read_data<={read_data[6:0],sda_sync[2]};
     state<=FALL;
    end
    FALL:begin
     scl_low<=1;
     if(bit_number<8)begin bit_number<=bit_number+1'b1;state<=LOW;end
     else if(error)state<=STOP_LOW;
     else case(stage)
      0:send_byte(reg_addr,0,1);
      1:if(rd)state<=RESTART_LOW;else send_byte(data,0,2);
      3:send_byte(8'hff,1,4);
      default:state<=STOP_LOW;
     endcase
    end
    RESTART_LOW:begin sda_low<=0;state<=RESTART_RISE;end
    RESTART_RISE:begin scl_low<=0;if(!scl_low&&scl_sync[2])state<=RESTART_START;end
    RESTART_START:begin sda_low<=1;state<=START;send_byte({addr,1'b1},0,3);end
    STOP_LOW:begin scl_low<=1;sda_low<=1;state<=STOP_RISE;end
    STOP_RISE:begin scl_low<=0;if(!scl_low&&scl_sync[2])state<=STOP_RELEASE;end
    STOP_RELEASE:begin sda_low<=0;state<=FINISH;end
    RECOVER:if(scl_sync[2])state<=STOP_RELEASE;
    FINISH:begin done<=1;state<=IDLE;end
    default:begin scl_low<=0;sda_low<=0;end
   endcase
  end
 end
endmodule
