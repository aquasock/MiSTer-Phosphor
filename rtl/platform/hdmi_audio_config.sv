// ADV7513 audio-rate register update under an exclusive I2C lease.
// Caller must mute/drain output before request and keep it muted on failure.
// mode: 0 movie 48 kHz, 1 native CD 44.1 kHz, 2 inherited movie 96 kHz output.
// Read-modify-write preserves unrelated fields; all five values are read back.
module hdmi_audio_config #(
 parameter integer QUARTER_CYCLES=125,
 parameter integer STRETCH_LIMIT=250000,
 parameter integer GRANT_LIMIT=1000000
)(
 input wire clk,reset,request,
 input wire[1:0] mode,
 output wire ready,
 output reg done,error,
 output wire local_request,local_done,
 input wire local_grant,
 input wire pad_scl,pad_sda,
 output wire local_scl_low,local_sda_low
);
 localparam IDLE=0,ACQUIRE=1,ISSUE=2,WAIT=3,RELEASE=4;
 localparam GW=$clog2(GRANT_LIMIT+1);
 reg[2:0] state,index;reg[1:0] pass,selected_mode;
 reg[7:0] target[0:4];reg[GW-1:0] grant_count;
 wire master_ready,master_done,master_error;wire[7:0] read_data;
 reg[7:0] register_address;
 always @*case(index)
  0:register_address=8'h0a;
  1:register_address=8'h15;
  2:register_address=8'h01;
  3:register_address=8'h02;
  default:register_address=8'h03;
 endcase
 assign ready=state==IDLE&&!reset;
 assign local_request=state!=IDLE;
 assign local_done=state==RELEASE;
 i2c_register_master #(.QUARTER_CYCLES(QUARTER_CYCLES),.STRETCH_LIMIT(STRETCH_LIMIT)) master(
  .clk(clk),.reset(reset),.request(state==ISSUE&&local_grant),.read_register(pass!=1),
  .address(7'h39),.register_address(register_address),.write_data(target[index]),
  .ready(master_ready),.done(master_done),.error(master_error),.read_data(read_data),
  .pad_scl(pad_scl),.pad_sda(pad_sda),.scl_low(local_scl_low),.sda_low(local_sda_low));
 integer i;
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;index<=0;pass<=0;selected_mode<=0;done<=0;error<=0;grant_count<=0;
   for(i=0;i<5;i=i+1)target[i]<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(request)begin
     error<=0;index<=0;pass<=0;selected_mode<=mode;grant_count<=0;
     if(mode==3)begin error<=1;done<=1;end else state<=ACQUIRE;
    end
    ACQUIRE:if(local_grant)state<=ISSUE;
     else if(grant_count==GW'(GRANT_LIMIT-1))begin error<=1;state<=RELEASE;end
     else grant_count<=grant_count+1'b1;
    ISSUE:if(master_ready&&local_grant)state<=WAIT;
    WAIT:if(master_done)begin
     if(master_error||(pass==2&&read_data!=target[index])||(pass==0&&index==0&&read_data[6:4]!=0))begin error<=1;state<=RELEASE;end
     else begin
      if(pass==0)case(index)
       0:target[index]<=read_data&8'h7f; // automatic CTS
       1:target[index]<=(read_data&8'h0f)|(selected_mode==1?8'h00:selected_mode==2?8'ha0:8'h20);
       2:target[index]<=read_data&8'hf0; // N[19:16] = 0
       3:target[index]<=selected_mode==2?8'h30:8'h18;
       4:target[index]<=selected_mode==1?8'h80:8'h00; // N = 6272 / 6144 / 12288
       default:target[index]<=0;
      endcase
      if(index==4)begin
       index<=0;
       if(pass==2)state<=RELEASE;else begin pass<=pass+1'b1;state<=ISSUE;end
      end else begin index<=index+1'b1;state<=ISSUE;end
     end
    end
    RELEASE:if(!local_grant)begin done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
