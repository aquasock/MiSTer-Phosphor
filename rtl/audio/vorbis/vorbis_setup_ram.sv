module vorbis_setup_ram #(
 parameter WIDTH=8,parameter DEPTH=256,parameter ADDR_WIDTH=8,
 parameter INIT_FILE="UNUSED",parameter SIM_INIT_FILE=INIT_FILE
)(
 input wire clk,input wire write_enable,input wire [ADDR_WIDTH-1:0] write_address,
 input wire [WIDTH-1:0] write_data,input wire [ADDR_WIDTH-1:0] read_address,
 output wire [WIDTH-1:0] read_data
);
`ifdef SYNTHESIS
 wire [WIDTH-1:0] unused_q;
 altsyncram ram(
  .clock0(clk),.address_a(write_address),.data_a(write_data),.wren_a(write_enable),.q_a(unused_q),
  .address_b(read_address),.q_b(read_data),.wren_b(1'b0),.data_b({WIDTH{1'b0}}),
  .aclr0(1'b0),.aclr1(1'b0),.addressstall_a(1'b0),.addressstall_b(1'b0),
  .byteena_a(1'b1),.byteena_b(1'b1),.clocken0(1'b1),.clocken1(1'b1),.clocken2(1'b1),.clocken3(1'b1),
  .eccstatus(),.rden_a(1'b1),.rden_b(1'b1));
 defparam ram.numwords_a=DEPTH,ram.widthad_a=ADDR_WIDTH,ram.width_a=WIDTH,
  ram.numwords_b=DEPTH,ram.widthad_b=ADDR_WIDTH,ram.width_b=WIDTH,
  ram.address_reg_b="CLOCK0",ram.intended_device_family="Cyclone V",ram.lpm_type="altsyncram",
  ram.operation_mode="DUAL_PORT",ram.outdata_reg_a="UNREGISTERED",ram.outdata_reg_b="UNREGISTERED",
  ram.power_up_uninitialized="FALSE",ram.init_file=INIT_FILE,ram.read_during_write_mode_port_a="DONT_CARE",
  ram.read_during_write_mode_port_b="DONT_CARE",ram.width_byteena_a=1,ram.width_byteena_b=1;
`else
 reg [WIDTH-1:0] memory[0:DEPTH-1];
 reg [WIDTH-1:0] simulation_read_data;
 initial if(SIM_INIT_FILE!="UNUSED")$readmemh(SIM_INIT_FILE,memory);
 assign read_data=simulation_read_data;
 always @(posedge clk)begin
  if(write_enable)memory[write_address]<=write_data;
  simulation_read_data<=memory[read_address];
 end
`endif
endmodule
