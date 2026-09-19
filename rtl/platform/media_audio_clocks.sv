// Additional native CD PLL; the existing movie/STC clock is never reclocked.
// Select/enable are held by the muted handoff controller. Consumers must
// acknowledge clock settling before releasing serializers or audible data.
module media_audio_clocks(
 input wire refclk,reset,movie_clock,select_cd,cd_48k,enable,
 output wire cd_clock,cd_locked,output_clock
);
 wire cd_clock_44,cd_clock_48,locked_44,locked_48;
 altera_pll #(
  .fractional_vco_multiplier("true"),.reference_clock_frequency("50.0 MHz"),
  .operation_mode("direct"),.number_of_clocks(1),
  .output_clock_frequency0("22.579200 MHz"),.phase_shift0("0 ps"),.duty_cycle0(50),
  .pll_type("General"),.pll_subtype("General")
 ) cd_pll_44(.refclk(refclk),.rst(reset),.outclk(cd_clock_44),.locked(locked_44),.fboutclk(),.fbclk(1'b0));
 altera_pll #(
  .fractional_vco_multiplier("true"),.reference_clock_frequency("50.0 MHz"),
  .operation_mode("direct"),.number_of_clocks(1),
  .output_clock_frequency0("24.576000 MHz"),.phase_shift0("0 ps"),.duty_cycle0(50),
  .pll_type("General"),.pll_subtype("General")
 ) cd_pll_48(.refclk(refclk),.rst(reset),.outclk(cd_clock_48),.locked(locked_48),.fboutclk(),.fbclk(1'b0));

 // Cyclone V provides only two PLL-capable inputs on a hard clock-control
 // block. This audio-player core therefore dedicates them to the two native
 // sample-rate families. The inherited movie stream remains independently
 // clocked; while it owns the pins, this selected native MCLK is merely idle.
 // The OFF -> SELECT -> ON sequence prevents a truncated output cycle.
 reg[1:0] selected=2;reg gate=0;reg[1:0] state=0;reg[3:0] delay_count=0;
 wire[1:0] requested=cd_48k ? 2'd3 : 2'd2;
 (* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
 reg[2:0] cd44_gate_sync=0,cd48_gate_sync=0;
 wire selected_gate=(selected==2'd3) ? cd48_gate_sync[2] :
                    cd44_gate_sync[2];
 always @(posedge cd_clock_44)cd44_gate_sync<={cd44_gate_sync[1:0],gate};
 always @(posedge cd_clock_48)cd48_gate_sync<={cd48_gate_sync[1:0],gate};
 always @(posedge refclk)begin
  if(reset)begin selected<=2;gate<=0;state<=0;delay_count<=0;end
  else case(state)
   0:begin
    gate<=0;
    if(&delay_count)begin selected<=requested;delay_count<=0;state<=1;end
    else delay_count<=delay_count+1'b1;
   end
   1:begin
    if(&delay_count)begin
     delay_count<=0;
     if(selected!=requested)state<=0;
     else if(enable)begin gate<=1;state<=2;end
    end else delay_count<=delay_count+1'b1;
   end
   2:if(selected!=requested||!enable)begin gate<=0;delay_count<=0;state<=0;end
   default:begin gate<=0;state<=0;delay_count<=0;end
  endcase
 end
 altclkctrl #(.clock_type("Global Clock"),.number_of_clocks(4),.width_clkselect(2),
  .ena_register_mode("falling edge"),.use_glitch_free_switch_over_implementation("OFF"))
 selector(.inclk({cd_clock_48,cd_clock_44,2'b00}),.clkselect(selected),
  .ena(selected_gate),.outclk(output_clock));
 assign cd_clock=output_clock;
 assign cd_locked=(selected==2'd3) ? locked_48 : locked_44;
endmodule
