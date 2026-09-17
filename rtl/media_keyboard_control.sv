// One command per physical key press. Track releases even while OSD is open,
// so menu navigation and typematic repeats cannot leak into playback.
module media_keyboard_control #(parameter RESTART_BOTH_DIRECTIONS=0,parameter ENABLE_SEEK_GATE=0)(
 input wire clk,reset,new_file,enabled,osd_open,
 input wire [10:0] key,
 input wire [34:0] elapsed_q,duration_q,seek_origin_q,
 input wire duration_valid,
 input wire seek_done,restart_complete,seek_enabled,
 output reg paused=0,seek_active=0,
 output reg [34:0] seek_target_q=0,
 output reg restart=0
);
reg key_toggle=0;
reg space_down=0,left_down=0,right_down=0;
reg [1:0] ctrl_down=0,alt_down=0;
reg wait_restart=0;
reg [7:0] function_down=0;
reg [2:0] section;
always @* begin
 case(key[8:0])
  9'h005:section=0;9'h006:section=1;9'h004:section=2;9'h00c:section=3;
  9'h003:section=4;9'h00b:section=5;9'h083:section=6;9'h00a:section=7;
  default:section=0;
 endcase
end
// Widen before shift/add; even the maximum duration times seven cannot wrap.
// Dividing the final sum preserves fractional-eighth precision without a DSP.
wire [37:0] section_product=(section[0]?{3'b0,duration_q}:38'd0)
                         +(section[1]?{2'b0,duration_q,1'b0}:38'd0)
                         +(section[2]?{1'b0,duration_q,2'b0}:38'd0);
wire [35:0] section_absolute={1'b0,section_product[37:3]}+{1'b0,seek_origin_q};
wire [34:0] section_target=section_absolute[35]?{35{1'b1}}:section_absolute[34:0];
wire ctrl=|ctrl_down;
wire alt=|alt_down;
wire [34:0] jump_q=ctrl ? (alt ? 35'd21600000 : 35'd10800000) : 35'd3600000;
wire [35:0] forward_q={1'b0,elapsed_q}+{1'b0,jump_q};
always @(posedge clk) begin
 restart<=0;
 key_toggle<=key[10];
 if(reset) begin
  paused<=0;seek_active<=0;seek_target_q<=0;wait_restart<=0;
  space_down<=0;left_down<=0;right_down<=0;ctrl_down<=0;alt_down<=0;function_down<=0;
 end else begin
  if(restart_complete) wait_restart<=0;
  // While retiring a backward restart, the old elapsed time already exceeds
  // the new target. Its completion must not acknowledge the new session.
  if(seek_done&&!wait_restart) seek_active<=0;
  if(new_file) begin paused<=0;seek_active<=0;seek_target_q<=0;wait_restart<=0;end
  if(key_toggle!=key[10]) begin
   case(key[8:0])
    9'h014:ctrl_down[0]<=key[9];
    9'h114:ctrl_down[1]<=key[9];
    9'h011:alt_down[0]<=key[9];
    9'h111:alt_down[1]<=key[9];
    9'h029:begin
     space_down<=key[9];
     if(key[9]&&!space_down&&enabled&&!osd_open&&!new_file) paused<=!paused;
    end
    9'h005,9'h006,9'h004,9'h00c,9'h003,9'h00b,9'h083,9'h00a:begin
     function_down[section]<=key[9];
     if(key[9]&&!function_down[section]&&enabled&&!osd_open&&!new_file&&
        !seek_active&&!seek_done&&duration_valid&&duration_q!=0&&
        (!ENABLE_SEEK_GATE||seek_enabled)) begin
      seek_target_q<=section_target;
      seek_active<=1;
      restart<=RESTART_BOTH_DIRECTIONS || section_target<elapsed_q;
      wait_restart<=RESTART_BOTH_DIRECTIONS || section_target<elapsed_q;
     end
    end
    9'h16b,9'h174:begin
     if(key[8:0]==9'h16b) left_down<=key[9];else right_down<=key[9];
     if(key[9]&&!(key[8:0]==9'h16b ? left_down:right_down)&&enabled&&
        !osd_open&&!new_file&&!seek_active&&!seek_done&&(!ENABLE_SEEK_GATE||seek_enabled)) begin
      if(key[8:0]==9'h16b) seek_target_q<=elapsed_q<jump_q?35'd0:elapsed_q-jump_q;
      else seek_target_q<=forward_q[35]?{35{1'b1}}:forward_q[34:0];
      // Legacy integrations may retain forward reconstruction. Production
      // direct seeking restarts either direction through the same search.
      seek_active<=1;restart<=RESTART_BOTH_DIRECTIONS || key[8:0]==9'h16b;
      wait_restart<=RESTART_BOTH_DIRECTIONS || key[8:0]==9'h16b;
     end
    end
   endcase
  end
 end
end
endmodule
