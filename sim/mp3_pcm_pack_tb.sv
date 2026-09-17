// Standalone functional testbench for mp3_pcm_pack.sv -- this module was
// never actually simulated before real hardware testing (audio_pcm_fifo.sv,
// which sits right after it in the real chain, uses an Altera dcfifo
// primitive Icarus can't simulate at all, so only "does it compile" was
// ever checked for this whole corner of the design). Written during
// hardware debugging of a garbled-audio bug that turned out to be a FIFO
// sizing/pacing issue downstream of this module, not a bug here -- this
// testbench confirmed that at the time, and now guards against a
// regression. Drives it with a synthetic mono-mode sequence resembling
// mp3_synthesis's real timing (sparse, gapped in_valid pulses, gci
// alternating 0/2 only) and checks fifo_wr_data against the expected
// {rate,stereo,left,right} packing.
`timescale 1ns/1ps
module mp3_pcm_pack_tb;

reg clk = 0;
always #5 clk = ~clk;

reg reset = 1;
reg new_file = 0;
reg frame_valid = 0;
reg frame_stereo = 0;
reg [1:0] frame_sr_idx = 0;
reg in_valid = 0;
reg [1:0] in_gci = 0;
reg signed [15:0] in_data = 0;

wire [34:0] fifo_wr_data;
wire fifo_wr_en;

mp3_pcm_pack dut (
    .clk(clk), .reset(reset),
    .new_file(new_file),
    .frame_valid(frame_valid), .frame_stereo(frame_stereo),
    .frame_sr_idx(frame_sr_idx),
    .in_valid(in_valid), .in_gci(in_gci), .in_data(in_data),
    .fifo_wr_data(fifo_wr_data), .fifo_wr_en(fifo_wr_en)
);

integer errors = 0;
integer i;

// Send a full stereo pair (gci=0 buffered, gci=1 triggers the paired
// write) and check the resulting L/R against expectation.
task send_stereo_pair(input signed [15:0] left_val, input signed [15:0] right_val);
    integer waited;
    begin
        @(posedge clk);
        in_valid <= 1'b1;
        in_gci <= 2'd0;
        in_data <= left_val;
        @(posedge clk);
        in_valid <= 1'b0;
        repeat (2) @(posedge clk); // gap, like real timing between channels

        @(posedge clk);
        in_valid <= 1'b1;
        in_gci <= 2'd1;
        in_data <= right_val;
        @(posedge clk);
        in_valid <= 1'b0;

        waited = 0;
        while (!fifo_wr_en && waited < 10) begin
            @(posedge clk);
            waited = waited + 1;
        end
        if (!fifo_wr_en) begin
            $display("FAIL: stereo pair L=%0d R=%0d: no fifo_wr_en within 10 cycles", left_val, right_val);
            errors = errors + 1;
        end else if (fifo_wr_data[32] !== 1'b1) begin
            $display("FAIL: stereo pair L=%0d R=%0d: expected stereo=1, got %b", left_val, right_val, fifo_wr_data[32]);
            errors = errors + 1;
        end else if ($signed(fifo_wr_data[31:16]) !== left_val || $signed(fifo_wr_data[15:0]) !== right_val) begin
            $display("FAIL: stereo pair expected L=%0d R=%0d, got L=%0d R=%0d", left_val, right_val,
                $signed(fifo_wr_data[31:16]), $signed(fifo_wr_data[15:0]));
            errors = errors + 1;
        end else begin
            $display("PASS: stereo pair L=%0d R=%0d (waited %0d cycles)", left_val, right_val, waited);
        end
        @(posedge clk);
    end
endtask

// Send one sample and wait for the corresponding FIFO write to actually
// appear (mp3_pcm_pack's write is a registered pulse one cycle after
// in_valid is sampled, not combinational -- polling for it here instead
// of assuming a fixed cycle offset is what an earlier draft of this
// testbench got wrong, reporting spurious failures against a DUT that
// was actually correct).
task send_and_check(input [1:0] gci, input signed [15:0] data, input expect_write);
    integer waited;
    begin
        @(posedge clk);
        in_valid <= 1'b1;
        in_gci <= gci;
        in_data <= data;
        @(posedge clk);
        in_valid <= 1'b0;

        if (expect_write) begin
            waited = 0;
            while (!fifo_wr_en && waited < 10) begin
                @(posedge clk);
                waited = waited + 1;
            end
            if (!fifo_wr_en) begin
                $display("FAIL: gci=%0d data=%0d: no fifo_wr_en within 10 cycles", gci, data);
                errors = errors + 1;
            end else begin
                if (fifo_wr_data[34:33] !== 2'd0) begin
                    $display("FAIL: gci=%0d data=%0d: expected sr_idx=0 (44.1k file), got %b", gci, data, fifo_wr_data[34:33]);
                    errors = errors + 1;
                end
                if (fifo_wr_data[32] !== 1'b0) begin
                    $display("FAIL: gci=%0d data=%0d: expected stereo=0 (mono file), got %b", gci, data, fifo_wr_data[32]);
                    errors = errors + 1;
                end
                if ($signed(fifo_wr_data[31:16]) !== data || $signed(fifo_wr_data[15:0]) !== data) begin
                    $display("FAIL: gci=%0d expected L=R=%0d, got L=%0d R=%0d", gci, data,
                        $signed(fifo_wr_data[31:16]), $signed(fifo_wr_data[15:0]));
                    errors = errors + 1;
                end else begin
                    $display("PASS: gci=%0d data=%0d -> L=R=%0d (waited %0d cycles)", gci, data, data, waited);
                end
            end
        end
        // drain the write pulse before the next send
        @(posedge clk);
    end
endtask

initial begin
    #12 reset = 0;

    // Mono file: gci alternates 0 (granule0) and 2 (granule1) only.
    // frame_valid pulses once, well before any real sample arrives,
    // exactly like the real pipeline's huge cumulative latency.
    @(posedge clk);
    frame_stereo = 0;
    frame_sr_idx = 2'd0; // 44.1kHz
    frame_valid = 1;
    @(posedge clk);
    frame_valid = 0;

    repeat (20) @(posedge clk); // idle gap matching real upstream latency

    for (i = 0; i < 8; i = i + 1)
        send_and_check(2'd0, i * 100 - 350, 1'b1);

    for (i = 0; i < 4; i = i + 1)
        send_and_check(2'd2, i * 50 + 17, 1'b1);

    // Now switch this same instance to stereo mode: new_file + a fresh
    // frame_valid with frame_stereo=1, matching a new file being loaded.
    @(posedge clk);
    new_file = 1;
    @(posedge clk);
    new_file = 0;
    repeat (5) @(posedge clk);
    frame_stereo = 1;
    frame_sr_idx = 2'd1; // 48kHz this time
    frame_valid = 1;
    @(posedge clk);
    frame_valid = 0;
    repeat (20) @(posedge clk);

    for (i = 0; i < 6; i = i + 1)
        send_stereo_pair(i * 100 - 250, i * 100 - 200);

    repeat (10) @(posedge clk);

    if (errors == 0) $display("RESULT: PASS (all mono checks passed)");
    else $display("RESULT: FAIL (%0d error(s))", errors);

    $finish;
end

initial begin
    #100000 begin
        $display("TIMEOUT");
        $finish;
    end
end

endmodule
