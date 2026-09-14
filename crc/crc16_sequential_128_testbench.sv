module crc16_sequential_128_testbench;
  timeunit 1ns;
  timeprecision 1ps;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst = 1;
  logic [143:0] input_data = 0;
  logic input_valid = 0;
  wire input_ready;
  wire [15:0] output_data;
  wire output_valid;
  logic output_ready = 0;
  logic [31:0] rng = 32'h12345678;
  logic [127:0] block_data;
  logic [15:0] initial_crc, expected, held;
  int cycles;

  crc16_sequential_128_test_dut dut(
    .clock(clk), .reset(rst),
    .input_data(input_data), .input_valid(input_valid), .input_ready(input_ready),
    .output_data(output_data), .output_valid(output_valid), .output_ready(output_ready)
  );
  tb_watchdog #(.MAX_CYCLES(50000)) watchdog(.clock(clk));

  function automatic logic [15:0] reference_crc(
    input logic [15:0] crc, input logic [127:0] data
  );
    logic [15:0] result;
    logic feedback;
    result = crc;
    for (int i = 127; i >= 0; --i) begin
      feedback = result[15] ^ data[i];
      result = result << 1;
      if (feedback) result ^= 16'h1021;
    end
    return result;
  endfunction

  task automatic reset_dut;
    @(negedge clk);
    rst = 1;
    input_valid = 0;
    output_ready = 0;
    repeat(3) @(negedge clk);
    rst = 0;
  endtask

  task automatic send_block(input logic [143:0] payload);
    @(negedge clk);
    input_data = payload;
    input_valid = 1;
    do @(posedge clk); while (!input_ready);
    @(negedge clk);
    input_valid = 0;
  endtask

  initial begin
    reset_dut();
    // Reset while a block is in flight; no stale result may survive.
    send_block('1);
    repeat(3) @(negedge clk);
    reset_dut();
    repeat(20) begin
      @(negedge clk);
      if (output_valid) $fatal(1, "stale output after reset");
    end
    // Present the next block while the first is still being processed.
    output_ready = 1;
    fork
      begin
        send_block(144'b0);
        send_block({16'hffff, 128'hffffffffffffffffffffffffffffffff});
      end
      begin
        for (int k = 0; k < 2; ++k) begin
          do @(posedge clk); while (!output_valid);
          if (output_data !== reference_crc(k == 0 ? 16'b0 : 16'hffff,
                                             k == 0 ? 128'b0 : {128{1'b1}}))
            $fatal(1, "back-to-back block mismatch");
          @(negedge clk);
        end
      end
    join
    output_ready = 0;
    expected = 0;
    for (int test_id = 0; test_id < 300; ++test_id) begin
      initial_crc = expected;
      for (int j = 0; j < 4; ++j) begin
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        block_data[j*32 +: 32] = rng;
      end
      if (test_id < 144) {initial_crc, block_data} = 144'b1 << test_id;
      expected = reference_crc(initial_crc, block_data);
      send_block({initial_crc, block_data});
      cycles = 0;
      while (!output_valid) begin
        @(negedge clk);
        cycles++;
      end
      if (output_data !== expected) $fatal(1, "CRC mismatch: test %0d", test_id);
      held = output_data;
      // Check output stability with downstream backpressure.
      repeat(test_id % 5) begin
        @(negedge clk);
        if (!output_valid || output_data !== held)
          $fatal(1, "unstable output under backpressure");
      end
      output_ready = 1;
      @(posedge clk);
      @(negedge clk);
      output_ready = 0;
    end
    repeat(20) begin
      @(negedge clk);
      if (output_valid) $fatal(1, "duplicate output");
    end
    $display("PASS: 302 sequential CRC blocks, reset, input and output backpressure");
    $finish;
  end
endmodule
