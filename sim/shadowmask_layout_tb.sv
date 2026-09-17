`timescale 1ns/1ps
module shadowmask_layout_tb;
reg clk=0,clk_sys=0,cmd_wr=0,hs=0,vs=0,de=0,brd=1,enable=0;
reg [15:0] cmd=0;
reg [23:0] rgb=0;
wire [23:0] rgb_out;
wire hs_out,vs_out,de_out,brd_out;
always #5 clk=~clk;
always #7 clk_sys=~clk_sys;

shadowmask dut(.clk(clk),.clk_sys(clk_sys),.cmd_wr(cmd_wr),.cmd_in(cmd),
 .din(rgb),.hs_in(hs),.vs_in(vs),.de_in(de),.brd_in(brd),.enable(enable),
 .dout(rgb_out),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.brd_out(brd_out));

reg [4:0] de_history=0,brd_history=0;
integer cycles=0;
always @(posedge clk) begin
 de_history<={de_history[3:0],de};brd_history<={brd_history[3:0],brd};cycles<=cycles+1;
 if(cycles>5)begin
  if(de_out!==de_history[4])$fatal(1,"DE latency mismatch");
  if(brd_out!==brd_history[4])$fatal(1,"border latency mismatch");
 end
end

initial begin
 repeat(3)@(negedge clk);de=1;brd=1;
 repeat(4)@(negedge clk);brd=0;
 repeat(7)@(negedge clk);brd=1;
 repeat(3)@(negedge clk);de=0;
 repeat(6)@(negedge clk);
 $display("PASS HDMI content-border marker remains aligned with DE");
 $finish;
end
endmodule
