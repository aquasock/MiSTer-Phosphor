// Additional native CD PLL; the existing movie/STC clock is never reclocked.
// Select/enable are held by the muted handoff controller. Consumers must
// acknowledge clock settling before releasing serializers or audible data.
module media_audio_clocks(
 input wire refclk,reset,movie_clock,select_cd,enable,
 output wire cd_clock,cd_locked,output_clock
);
 altera_pll #(
  .fractional_vco_multiplier("true"),.reference_clock_frequency("50.0 MHz"),
  .operation_mode("direct"),.number_of_clocks(1),
  .output_clock_frequency0("22.579200 MHz"),.phase_shift0("0 ps"),.duty_cycle0(50),
  .pll_type("General"),.pll_subtype("General")
 ) cd_pll(.refclk(refclk),.rst(reset),.outclk(cd_clock),.locked(cd_locked),.fboutclk(),.fbclk(1'b0));
 // The vendor's optional soft glitch-free wrapper powers up on input 0,
 // which cannot be a PLL on Cyclone V. Use the hard falling-edge gate with
 // an explicit OFF -> SELECT -> ON sequence, starting on PLL input 2.
 // Sixteen 50 MHz cycles exceed the three-stage enable crossing plus
 // falling-edge gate latency for either audio clock.
 reg selected=0,gate=0;reg[1:0] state=0;reg[3:0] delay_count=0;
 (* preserve, altera_attribute="-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
 reg[2:0] cd_gate_sync=0,movie_gate_sync=0;
 always @(posedge cd_clock)cd_gate_sync<={cd_gate_sync[1:0],gate};
 always @(posedge movie_clock)movie_gate_sync<={movie_gate_sync[1:0],gate};
 always @(posedge refclk)begin
  if(reset)begin gate<=0;state<=0;delay_count<=0;end
  else case(state)
   0:begin
    gate<=0;
    if(&delay_count)begin selected<=select_cd;delay_count<=0;state<=1;end
    else delay_count<=delay_count+1'b1;
   end
   1:begin
    if(&delay_count)begin
     delay_count<=0;
     if(selected!=select_cd)state<=0;
     else if(enable)begin gate<=1;state<=2;end
    end else delay_count<=delay_count+1'b1;
   end
   2:if(selected!=select_cd||!enable)begin gate<=0;delay_count<=0;state<=0;end
   default:begin gate<=0;state<=0;delay_count<=0;end
  endcase
 end
 altclkctrl #(.clock_type("Global Clock"),.number_of_clocks(4),.width_clkselect(2),
  .ena_register_mode("falling edge"),.use_glitch_free_switch_over_implementation("OFF"))
 selector(.inclk({cd_clock,movie_clock,2'b00}),.clkselect({1'b1,selected}),.ena(selected?cd_gate_sync[2]:movie_gate_sync[2]),.outclk(output_clock));
endmodule
