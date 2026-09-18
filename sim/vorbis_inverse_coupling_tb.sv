`timescale 1ns/1ps
module vorbis_inverse_coupling_tb;
 reg clk=0,reset=1,start=0,set_seed_valid=0,read_check_valid=0;
 reg [11:0] seed_address=0,check_address=0;reg signed [31:0] seed_value=0;
 wire coupling_read_valid,coupling_set_valid,workspace_read_ready,workspace_set_ready;
 wire [11:0] coupling_read_address,coupling_set_address;wire signed [31:0] coupling_set_value;
 wire workspace_read_valid=start_done?read_check_valid:coupling_read_valid;
 wire [11:0] workspace_read_address=start_done?check_address:coupling_read_address;
 wire workspace_set_valid=start_done?set_seed_valid:coupling_set_valid;
 wire [11:0] workspace_set_address=start_done?seed_address:coupling_set_address;
 wire signed [31:0] workspace_set_value=start_done?seed_value:coupling_set_value;
 wire read_data_valid,clear_ready,clear_done,add_ready,read_ready,set_ready,done,error;
 wire signed [31:0] read_data;wire [7:0] coupling_query;reg start_done=1;
 always #5 clk=~clk;
 vorbis_residue_workspace workspace(.clk(clk),.reset(reset),.clear_start(1'b0),.clear_length(13'd0),
  .clear_ready(clear_ready),.clear_done(clear_done),.add_valid(1'b0),.add_ready(add_ready),
  .add_address(12'd0),.add_value(32'sd0),.set_valid(workspace_set_valid),.set_ready(workspace_set_ready),
  .set_address(workspace_set_address),.set_value(workspace_set_value),.read_valid(workspace_read_valid),
  .read_ready(workspace_read_ready),.read_address(workspace_read_address),
  .read_data_valid(read_data_valid),.read_data(read_data));
 vorbis_inverse_coupling dut(.clk(clk),.reset(reset),.start(start),.coupling_steps(9'd1),
  .spectral_bins(12'd4),.coupling_query(coupling_query),.coupling_magnitude(1'b0),.coupling_angle(1'b1),
  .read_valid(coupling_read_valid),.read_ready(workspace_read_ready),.read_address(coupling_read_address),
  .read_data_valid(read_data_valid),.read_data(read_data),.set_valid(coupling_set_valid),
  .set_ready(workspace_set_ready),.set_address(coupling_set_address),.set_value(coupling_set_value),
  .ready(),.done(done),.error(error));
 task seed;input [11:0] address;input signed [31:0] value;begin
  @(negedge clk);while(!workspace_set_ready)@(negedge clk);
  seed_address=address;seed_value=value;set_seed_valid=1;@(negedge clk);set_seed_valid=0;
 end endtask
 task check;input [11:0] address;input signed [31:0] expected;begin
  @(negedge clk);while(!workspace_read_ready)@(negedge clk);
  check_address=address;read_check_valid=1;@(negedge clk);read_check_valid=0;
  while(read_data_valid)@(negedge clk);while(!read_data_valid)@(negedge clk);
  if(read_data!==expected)$fatal(1,"address %0d expected %h got %h",address,expected,read_data);
 end endtask
 initial begin
  repeat(3)@(negedge clk);reset=0;
  seed(0,10<<<16);seed(1,3<<<16);seed(2,10<<<16);seed(3,-3<<<16);
  seed(4,-10<<<16);seed(5,3<<<16);seed(6,-10<<<16);seed(7,-3<<<16);
  start_done=0;@(negedge clk);start=1;@(negedge clk);start=0;wait(done||error);
  if(error)$fatal(1,"coupling error");start_done=1;
  check(0,10<<<16);check(1,7<<<16);check(2,7<<<16);check(3,10<<<16);
  check(4,-10<<<16);check(5,-7<<<16);check(6,-7<<<16);check(7,-10<<<16);
  $display("PASS inverse coupling all four magnitude/angle sign quadrants");$finish;
 end
 initial begin repeat(2000)@(posedge clk);$fatal(1,"timeout state=%0d",dut.state);end
endmodule
