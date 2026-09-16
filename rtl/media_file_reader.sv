// Stock Main mounted-file reader. A whole bounded response is buffered before
// decoder backpressure is allowed. sd_ack brackets a transfer, not its first
// data word; hps_io pipelines the final buffer write beyond acknowledgement.
module media_file_reader #(
    parameter integer TIMEOUT_CYCLES=100000000
)(
    input wire clk,reset,start,cancel,suspend,
    input wire [63:0] file_size,start_offset,
    output reg [31:0] sd_lba=0,
    output reg [5:0] sd_blk_cnt=0,
    output reg sd_rd=0,
    input wire sd_ack,sd_buff_wr,
    input wire [12:0] sd_buff_addr,
    input wire [15:0] sd_buff_dout,
    output wire [8:0] stream_data,
    output wire stream_valid,
    input wire stream_ready,
    output wire idle,
    output reg [63:0] byte_position=0,
    output reg [31:0] requests=0,completions=0,max_wait=0,
    output reg [3:0] error=0
);
localparam IDLE=0,PREPARE=1,WAIT_ACK=2,RECEIVE=3,TAIL=4,FETCH=5,SEND=6,END_FILE=7;
reg [3:0] state=IDLE;
reg [63:0] size=0;
reg [12:0] pos=0,limit=0;
reg [11:0] words=0,expected_words=0;
reg [2:0] settle=0;
reg [31:0] wait_cycles=0;
reg bad_response=0,aborted=0;
reg [15:0] staging[0:2047];
reg [15:0] word_q;
wire receiving=state==WAIT_ACK || state==RECEIVE || state==TAIL;
wire [63:0] remaining=size-byte_position;
wire [63:0] span=remaining+{55'd0,byte_position[8:0]};
wire [12:0] batch_bytes=span>=4096 ? 13'd4096 : span[12:0];
wire [3:0] sectors=batch_bytes[12:9]+ {3'd0,(|batch_bytes[8:0])};
assign idle=state==IDLE && !sd_ack;
assign stream_valid=!cancel && !aborted && (state==SEND || state==END_FILE);
assign stream_data=state==END_FILE ? 9'h100 : {1'b0,pos[0]?word_q[15:8]:word_q[7:0]};
always @(posedge clk) begin
    // Synchronous inferred RAM read, independent of reset/control muxes.
    word_q<=staging[pos[11:1]];
    if(receiving && sd_buff_wr && sd_buff_addr<2048)
        staging[sd_buff_addr[10:0]]<=sd_buff_dout;
    if(reset) begin
        state<=IDLE;sd_rd<=0;byte_position<=0;size<=0;
        requests<=0;completions<=0;max_wait<=0;error<=0;
        words<=0;expected_words<=0;bad_response<=0;aborted<=0;
        wait_cycles<=0;settle<=0;pos<=0;limit<=0;
    end else begin
        if(receiving && sd_buff_wr) begin
            words<=words+1'b1;
            if(sd_buff_addr!={1'b0,words} || words>=expected_words)
                bad_response<=1;
        end
        if(receiving) begin
            if(wait_cycles<TIMEOUT_CYCLES) wait_cycles<=wait_cycles+1'b1;
            else begin error<=1;aborted<=1; end
            // Never recycle an outstanding request on timeout. Drain its late
            // acknowledgement before accepting another session.
            if(cancel) aborted<=1;
        end
        case(state)
        IDLE: if(start && !cancel && !sd_ack) begin
            byte_position<=start_offset;size<=file_size;
            requests<=0;completions<=0;max_wait<=0;error<=0;aborted<=0;
            if(start_offset>file_size || file_size>64'h20000000000) error<=3;
            else state<=PREPARE;
        end
        PREPARE: if(cancel) state<=IDLE;
        else if(byte_position==size) state<=END_FILE;
        else if(!suspend) begin
            sd_lba<=byte_position[40:9];sd_blk_cnt<={2'd0,sectors}-1'b1;
            pos<={4'd0,byte_position[8:0]};limit<=batch_bytes;
            expected_words<={sectors,8'd0};words<=0;bad_response<=0;
            sd_rd<=1;wait_cycles<=0;requests<=requests+1'b1;state<=WAIT_ACK;
        end
        WAIT_ACK: if(sd_ack) begin sd_rd<=0;state<=RECEIVE;end
        RECEIVE: if(!sd_ack) begin settle<=4;state<=TAIL;end
        TAIL: if(settle!=0) settle<=settle-1'b1;
        else begin
            completions<=completions+1'b1;
            if(wait_cycles>max_wait) max_wait<=wait_cycles;
            if(cancel || aborted) state<=IDLE;
            else if(bad_response || words!=expected_words) begin error<=2;state<=IDLE;end
            else state<=FETCH;
        end
        FETCH: if(cancel) state<=IDLE;else state<=SEND;
        SEND: if(cancel) state<=IDLE;
        else if(stream_ready) begin
            byte_position<=byte_position+1'b1;pos<=pos+1'b1;
            if(pos+1'b1==limit) state<=PREPARE;
            else if(pos[0]) state<=FETCH;
        end
        END_FILE: if(cancel || stream_ready) state<=IDLE;
        default: state<=IDLE;
        endcase
    end
end
endmodule
