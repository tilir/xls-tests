// Self-checking, latency-independent testbench for the generated CRC-16/XMODEM
// streaming proc.
//
// The DUT instantiated below is a simulation-only wrapper generated from the
// XLS ModuleSignatureProto. It exposes stable channel-oriented names, keeping
// this hand-written testbench independent of physical names such as `_input`
// that codegen_main may choose for the actual RTL module. The wrapper is not
// part of the Yosys synthesis target.
//
// The input channel payload is the packed DSLX Input struct: data occupies
// bits [8:1] and last occupies bit [0]. Every accepted byte updates a
// CRC-16/XMODEM accumulator initialized to zero. A byte with last=1 completes
// the packet, emits its CRC on the output channel, and resets the accumulator
// for the next packet.
//
// Stimulus and result checking are deliberately decoupled. The driver holds
// valid and payload until an input ready/valid handshake. Packet results from
// the independent reference model are queued, while the output monitor removes
// and compares them only on an output handshake. Consequently the test does
// not assume a particular codegen latency or combinational ready path.
//
// Covered scenarios are the standard "123456789" check vector, all 256
// possible one-byte packets, output backpressure with stable valid/data, and
// deterministic pseudo-random multi-byte packets. The shared watchdog turns a
// handshake deadlock into a finite test failure.
//
// Runtime options: +verbose prints successful checks; +trace writes crc16.fst.
module crc16_testbench;
  timeunit 1ns;
  timeprecision 1ps;

  import tb_util_pkg::*;

  localparam int MAX_RESULTS = 1024;

  logic        clk;
  logic        rst;
  logic [8:0]  input_data;
  logic        input_vld;
  logic        output_rdy;
  logic        input_rdy;
  logic [15:0] output_data;
  logic        output_vld;

  logic [15:0] expected_results [0:MAX_RESULTS-1];
  int unsigned expected_count;
  int unsigned received_count;

  // crc16_test_dut is generated in the build tree from
  // crc16.signature.textproto; it contains wiring only.
  crc16_test_dut dut (
    .clock(clk),
    .reset(rst),
    .input_data(input_data),
    .input_valid(input_vld),
    .input_ready(input_rdy),
    .output_data(output_data),
    .output_valid(output_vld),
    .output_ready(output_rdy)
  );

  tb_watchdog #(.MAX_CYCLES(10000)) watchdog (.clock(clk));

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Bit-serial reference model kept structurally independent of generated RTL.
  function automatic logic [15:0] crc16_byte_ref(
    input logic [15:0] crc,
    input logic [7:0] data
  );
    logic [15:0] result;
    logic feedback;
    result = crc;
    for (int bit_index = 7; bit_index >= 0; --bit_index) begin
      feedback = result[15] ^ data[bit_index];
      result = result << 1;
      if (feedback)
        result = result ^ 16'h1021;
    end
    return result;
  endfunction

  function automatic logic [7:0] check_vector_byte(input int index);
    case (index)
      0: return "1";
      1: return "2";
      2: return "3";
      3: return "4";
      4: return "5";
      5: return "6";
      6: return "7";
      7: return "8";
      8: return "9";
      default: return 8'h00;
    endcase
  endfunction

  // Fixed-size queue avoids relying on simulator-specific dynamic queue
  // support while allowing input and output activity to proceed independently.
  task automatic expect_result(input logic [15:0] expected);
    if (expected_count == MAX_RESULTS)
      $fatal(1, "Expected-result queue overflow");
    expected_results[expected_count] = expected;
    expected_count = expected_count + 1;
  endtask

  task automatic wait_for_results(input int unsigned target_count);
    while (received_count < target_count)
      @(posedge clk);
  endtask

  task automatic reset_dut;
    @(negedge clk);
    rst = 1;
    input_vld = 0;
    output_rdy = 0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    output_rdy = 1;
  endtask

  // Hold valid and payload until the DUT accepts the transfer. No assumption
  // is made about ready latency or internal buffering.
  task automatic send_byte(input logic [7:0] data, input logic last);
    @(negedge clk);
    input_data = {data, last};
    input_vld = 1;
    do begin
      @(posedge clk);
    end while (!input_rdy);
    @(negedge clk);
    input_vld = 0;
  endtask

  task automatic test_known_vector;
    logic [15:0] expected;
    int unsigned target_count;
    begin_test("123456789 check vector");
    expected = 0;
    for (int index = 0; index < 9; ++index) begin
      expected = crc16_byte_ref(expected, check_vector_byte(index));
      if (index == 8)
        expect_result(expected);
      send_byte(check_vector_byte(index), index == 8);
    end
    target_count = expected_count;
    wait_for_results(target_count);
    check("known.reference", expected, 16'h31c3, 16,
          "independent CRC-16/XMODEM reference");
    end_test("123456789 check vector");
  endtask

  task automatic test_single_byte_packets;
    logic [15:0] expected;
    int unsigned target_count;
    begin_test("single-byte packets");
    for (int data = 0; data < 256; ++data) begin
      expected = crc16_byte_ref(0, 8'(data));
      expect_result(expected);
      send_byte(8'(data), 1);
    end
    target_count = expected_count;
    wait_for_results(target_count);
    end_test("single-byte packets");
  endtask

  task automatic test_backpressure;
    logic [15:0] expected;
    logic [15:0] stalled_data;
    int unsigned target_count;
    begin_test("output backpressure");
    expected = crc16_byte_ref(0, 8'ha5);
    expect_result(expected);

    @(negedge clk);
    output_rdy = 0;
    input_data = {8'ha5, 1'b1};
    input_vld = 1;
    while (!output_vld)
      @(posedge clk);

    @(negedge clk);
    stalled_data = output_data;
    repeat (3) begin
      @(posedge clk);
      #1;
      check("stalled.valid", output_vld, 1, 1,
            "valid remains asserted under backpressure");
      check("stalled.data", output_data, stalled_data, 16,
            "data remains stable under backpressure");
    end

    @(negedge clk);
    output_rdy = 1;
    do begin
      @(posedge clk);
    end while (!input_rdy);
    @(negedge clk);
    input_vld = 0;
    target_count = expected_count;
    wait_for_results(target_count);
    end_test("output backpressure");
  endtask

  task automatic test_random_packets;
    logic [15:0] expected;
    logic [7:0] data;
    int packet_length;
    int unsigned seed;
    int unsigned target_count;
    begin_test("random packets");
    seed = 32'hc0decafe;
    void'($urandom(seed));
    for (int packet = 0; packet < 32; ++packet) begin
      expected = 0;
      packet_length = 1 + ($urandom % 24);
      for (int index = 0; index < packet_length; ++index) begin
        data = 8'($urandom);
        expected = crc16_byte_ref(expected, data);
        if (index == packet_length - 1)
          expect_result(expected);
        if (($urandom % 3) == 0)
          @(posedge clk);
        send_byte(data, index == packet_length - 1);
      end
    end
    target_count = expected_count;
    wait_for_results(target_count);
    end_test("random packets");
  endtask

  // Output timing is intentionally decoupled from the stimulus. Only a
  // ready/valid transfer causes a comparison with the expected-result queue.
  always @(posedge clk) begin
    if (!rst && output_vld && output_rdy) begin
      if (received_count >= expected_count) begin
        check("output.unexpected", 1, 0, 1, "no queued result");
      end else begin
        check("output.crc", output_data, expected_results[received_count], 16,
              $sformatf("result %0d", received_count));
      end
      received_count <= received_count + 1;
    end
  end

  initial begin
    rst = 0;
    input_data = 0;
    input_vld = 0;
    output_rdy = 0;
    expected_count = 0;
    received_count = 0;
    init_tests();

    if ($test$plusargs("trace")) begin
      $dumpfile("crc16.fst");
      $dumpvars(0, crc16_testbench);
    end

    reset_dut();
    test_known_vector();
    test_single_byte_packets();
    test_backpressure();
    test_random_packets();
    finish_tests("crc16");
  end
endmodule
