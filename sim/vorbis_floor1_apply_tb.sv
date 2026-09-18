`timescale 1ns/1ps
module vorbis_floor1_apply_tb;
 reg clk=0,reset=1,load_start=0,point_valid=0,apply_start=0,seed_valid=0,check_valid=0;
 reg [15:0] point_x=0;reg [8:0] point_y=0;reg point_active=0;
 reg [11:0] seed_address=0,check_address=0;reg signed [31:0] seed_value=0;
 wire point_ready,apply_read_valid,apply_set_valid,workspace_read_ready,workspace_set_ready;
 wire [11:0] apply_read_address,apply_set_address;wire signed [31:0] apply_set_value;
 reg use_apply=0;wire read_data_valid,done,error;wire signed [31:0] read_data;
 wire workspace_read_valid=use_apply?apply_read_valid:check_valid;
 wire [11:0] workspace_read_address=use_apply?apply_read_address:check_address;
 wire workspace_set_valid=use_apply?apply_set_valid:seed_valid;
 wire [11:0] workspace_set_address=use_apply?apply_set_address:seed_address;
 wire signed [31:0] workspace_set_value=use_apply?apply_set_value:seed_value;
 always #5 clk=~clk;
 vorbis_residue_workspace workspace(.clk(clk),.reset(reset),.clear_start(1'b0),.clear_length(13'd0),
  .clear_ready(),.clear_done(),.add_valid(1'b0),.add_ready(),.add_address(12'd0),.add_value(32'sd0),
  .set_valid(workspace_set_valid),.set_ready(workspace_set_ready),.set_address(workspace_set_address),
  .set_value(workspace_set_value),.read_valid(workspace_read_valid),.read_ready(workspace_read_ready),
  .read_address(workspace_read_address),.read_data_valid(read_data_valid),.read_data(read_data));
 vorbis_floor1_apply dut(.clk(clk),.reset(reset),.load_start(load_start),.point_valid(point_valid),
  .point_ready(point_ready),.point_x(point_x),.point_y(point_y),.point_active(point_active),
  .apply_start(apply_start),.floor_present(1'b1),.channel(1'b0),.spectral_bins(12'd4),.multiplier(3'd1),
  .read_valid(apply_read_valid),.read_ready(workspace_read_ready),.read_address(apply_read_address),
  .read_data_valid(read_data_valid),.read_data(read_data),.set_valid(apply_set_valid),
  .set_ready(workspace_set_ready),.set_address(apply_set_address),.set_value(apply_set_value),
  .ready(),.done(done),.error(error));
 task seed;input [11:0] address;begin
  @(negedge clk);seed_address=address;seed_value=32'sh00010000;seed_valid=1;
  @(negedge clk);seed_valid=0;
 end endtask
 task point;input [15:0] px;begin
  @(negedge clk);while(!point_ready)@(negedge clk);point_x=px;point_y=255;point_active=1;point_valid=1;
  @(negedge clk);point_valid=0;
 end endtask
 task check;input [11:0] address;input signed [31:0] expected;begin
  @(negedge clk);while(!workspace_read_ready)@(negedge clk);check_address=address;check_valid=1;
  @(negedge clk);check_valid=0;while(read_data_valid)@(negedge clk);while(!read_data_valid)@(negedge clk);
  if(read_data!==expected)$fatal(1,"address %0d expected %h got %h",address,expected,read_data);
 end endtask
 integer i;
 initial begin
  repeat(3)@(negedge clk);reset=0;
  for(i=0;i<4;i=i+1)seed(i*2);
  @(negedge clk);load_start=1;@(negedge clk);load_start=0;point(0);point(8);
  use_apply=1;@(negedge clk);apply_start=1;@(negedge clk);apply_start=0;wait(done||error);
  if(error)$fatal(1,"apply error");use_apply=0;
  check(0,32'sh0000ffff);check(2,32'sh0000ffff);check(4,32'sh0000ffff);check(6,32'sh0000ffff);
  for(i=0;i<4;i=i+1)seed(i*2);
  @(negedge clk);load_start=1;@(negedge clk);load_start=0;point(0);point(8);
  @(negedge clk);while(!point_ready)@(negedge clk);point_x=2;point_y=239;point_active=1;point_valid=1;
  @(negedge clk);point_valid=0;
  use_apply=1;@(negedge clk);apply_start=1;@(negedge clk);apply_start=0;wait(done||error);
  if(error)$fatal(1,"sloped apply error");use_apply=0;
  check(0,dut.inverse_db[255]>>15);check(2,dut.inverse_db[247]>>15);
  check(4,dut.inverse_db[239]>>15);check(6,dut.inverse_db[241]>>15);
  $display("PASS Floor-1 inverse-dB curve multiplied into residue spectrum");$finish;
 end
 initial begin repeat(3000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
