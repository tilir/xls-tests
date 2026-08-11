// Self-checking testbench for the generated CRC-16/XMODEM streaming proc.
// Runtime options: +verbose, +trace.
module crc16_testbench;
  timeunit 1ns;
  timeprecision 1ps;

  import tb_util_pkg::*;

  logic        clk;
  logic        rst;
  logic [8:0]  input_data;
  logic        input_vld;
  logic        output_rdy;
  logic        input_rdy;
  logic [15:0] output_data;
  logic        output_vld;

  crc16 dut (
    .clk(clk),
    .rst(rst),
    ._input(input_data),
    ._input_vld(input_vld),
    ._output_rdy(output_rdy),
    ._input_rdy(input_rdy),
    ._output(output_data),
    ._output_vld(output_vld)
  );

  tb_watchdog #(.MAX_CYCLES(5000)) watchdog (.clock(clk));

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

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

  task automatic reset_dut;
    @(negedge clk);
    rst = 1;
    input_vld = 0;
    output_rdy = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 0;
  endtask

  task automatic send_byte(input logic [7:0] data,
                           input logic last,
                           input logic [15:0] expected_crc);
    @(negedge clk);
    input_data = {data, last};
    input_vld = 1;
    output_rdy = 1;
    #1;
    check("input.ready", input_rdy, 1, 1,
          $sformatf("data=%02h last=%0b", data, last));
    check("output.valid", output_vld, last, 1,
          $sformatf("data=%02h last=%0b", data, last));
    if (last)
      check("output.crc", output_data, expected_crc, 16,
            $sformatf("final data=%02h", data));
    @(posedge clk);
    @(negedge clk);
    input_vld = 0;
    output_rdy = 0;
  endtask

  task automatic test_known_vector;
    logic [15:0] expected;
    begin_test("123456789 check vector");
    expected = 0;
    for (int index = 0; index < 9; ++index) begin
      expected = crc16_byte_ref(expected, check_vector_byte(index));
      send_byte(check_vector_byte(index), index == 8, expected);
    end
    check("known.crc", expected, 16'h31c3, 16,
          "independent CRC-16/XMODEM reference");
    end_test("123456789 check vector");
  endtask

  task automatic test_single_byte_packets;
    logic [15:0] expected;
    begin_test("single-byte packets");
    for (int data = 0; data < 256; ++data) begin
      expected = crc16_byte_ref(0, 8'(data));
      send_byte(8'(data), 1, expected);
    end
    end_test("single-byte packets");
  endtask

  task automatic test_backpressure;
    logic [15:0] expected;
    begin_test("output backpressure");
    expected = crc16_byte_ref(0, 8'ha5);

    @(negedge clk);
    input_data = {8'ha5, 1'b1};
    input_vld = 1;
    output_rdy = 0;
    #1;
    check("stalled.ready", input_rdy, 0, 1, "consumer is not ready");
    check("stalled.valid", output_vld, 1, 1, "result remains valid");
    check("stalled.crc", output_data, expected, 16, "result while stalled");
    repeat (3) begin
      @(posedge clk);
      #1;
      check("stalled.crc", output_data, expected, 16, "state held");
    end

    @(negedge clk);
    output_rdy = 1;
    #1;
    check("released.ready", input_rdy, 1, 1, "consumer became ready");
    check("released.crc", output_data, expected, 16, "accepted result");
    @(posedge clk);
    @(negedge clk);
    input_vld = 0;
    output_rdy = 0;

    expected = crc16_byte_ref(0, 8'h5a);
    send_byte(8'h5a, 1, expected);
    end_test("output backpressure");
  endtask

  task automatic test_random_packets;
    logic [15:0] expected;
    logic [7:0] data;
    int packet_length;
    int unsigned seed;
    begin_test("random packets");
    seed = 32'hc0decafe;
    void'($urandom(seed));
    for (int packet = 0; packet < 32; ++packet) begin
      expected = 0;
      packet_length = 1 + ($urandom % 24);
      for (int index = 0; index < packet_length; ++index) begin
        data = 8'($urandom);
        expected = crc16_byte_ref(expected, data);
        send_byte(data, index == packet_length - 1, expected);
        if (($urandom % 3) == 0)
          @(posedge clk);
      end
    end
    end_test("random packets");
  endtask

  initial begin
    rst = 0;
    input_data = 0;
    input_vld = 0;
    output_rdy = 0;
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
