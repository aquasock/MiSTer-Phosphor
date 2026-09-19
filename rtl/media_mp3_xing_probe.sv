// Inspect the first MPEG-1 Layer III frame's ancillary/main-data prefix for
// a Xing/Info frame count. The parser has already removed header, CRC and
// side information, so the signature is always at byte zero here.
module media_mp3_xing_probe(
 input wire clk,reset,input wire main_start,byte_valid,input wire [7:0] byte_data,
 output reg valid=0,output reg [31:0] frames=0
);
 reg first_seen=0,active=0;
 reg [4:0] position=0;
 reg [31:0] signature=0,flags=0,frame_field=0;
 always @(posedge clk)begin
  if(reset)begin first_seen<=0;active<=0;position<=0;valid<=0;frames<=0;signature<=0;flags<=0;frame_field<=0;end
  else begin
   if(main_start&&!first_seen)begin first_seen<=1;active<=1;position<=0;signature<=0;flags<=0;frame_field<=0;end
   if(active&&byte_valid)begin
    if(position<4)signature<={signature[23:0],byte_data};
    else if(position<8)flags<={flags[23:0],byte_data};
    else if(position<12)frame_field<={frame_field[23:0],byte_data};
    if(position==11)begin
     active<=0;
     if((signature==32'h58696e67||signature==32'h496e666f)&&flags[0])begin
      frames<={frame_field[23:0],byte_data};valid<={frame_field[23:0],byte_data}!=0;
     end
    end else position<=position+1'b1;
   end
  end
 end
endmodule
