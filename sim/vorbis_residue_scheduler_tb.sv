`timescale 1ns/1ps
module vorbis_residue_scheduler_tb;
 reg clk=0,reset=1,start=0;always #5 clk=~clk;
 wire [23:0] residue_begin=0,residue_end=64,partition_size=16;wire [6:0] classifications=3;
 wire [7:0] classbook=2,classbook_dimensions=2;wire [5:0] class_query;wire [2:0] pass_query;
 reg [7:0] class_cascade,pass_book;wire huffman_valid;reg huffman_ready=1;wire [7:0] huffman_book;
 reg symbol_valid=0;reg [17:0] symbol=0;wire task_valid;reg task_ready=1;wire [7:0] task_book;
 wire [2:0] task_pass;wire [6:0] task_partition;wire [23:0] task_offset,task_length;wire ready,done,error;
 vorbis_residue_scheduler dut(.*);
 integer classwords=0,tasks=0;
 always @* begin
  case(class_query)1:class_cascade=8'h03;2:class_cascade=8'h01;default:class_cascade=0;endcase
  if(class_query==1&&pass_query==0)pass_book=10;
  else if(class_query==1&&pass_query==1)pass_book=11;
  else if(class_query==2&&pass_query==0)pass_book=12;
  else pass_book=8'hff;
 end
 always @(posedge clk)begin
  symbol_valid<=0;
  if(huffman_valid&&huffman_ready)begin symbol<=classwords==0?5:3;symbol_valid<=1;classwords<=classwords+1;end
  if(task_valid&&task_ready)begin
   case(tasks)
    0:if(task_book!=10||task_pass!=0||task_partition!=0)$fatal(1,"task0");
    1:if(task_book!=12||task_pass!=0||task_partition!=1)$fatal(1,"task1");
    2:if(task_book!=10||task_pass!=0||task_partition!=2)$fatal(1,"task2");
    3:if(task_book!=11||task_pass!=1||task_partition!=0)$fatal(1,"task3");
    4:if(task_book!=11||task_pass!=1||task_partition!=2)$fatal(1,"task4");
    default:$fatal(1,"extra task %0d",tasks);
   endcase
   if(task_offset!=task_partition*16||task_length!=16)$fatal(1,"task range");
   tasks<=tasks+1;
  end
 end
 initial begin
  repeat(4)@(posedge clk);reset=0;@(negedge clk);start=1;@(negedge clk);start=0;
  repeat(500)begin @(negedge clk);if(done)begin
   if(error||classwords!=2||tasks!=5)$fatal(1,"result error=%0d words=%0d tasks=%0d",error,classwords,tasks);
   $display("PASS residue classwords expanded across eight passes");$finish;
  end end
  $fatal(1,"residue scheduler timeout state=%0d",dut.state);
 end
endmodule
