module crc16_naive_128_testbench #(parameter bit OPTIMIZED = 0);
  timeunit 1ns;
  timeprecision 1ps;

  logic [15:0] crc;
  logic [127:0] data;
  wire [15:0] out;
  logic [15:0] expected;
  logic [31:0] rng = 32'h12345678;

  generate
    if (OPTIMIZED) begin : optimized
      crc16_optimized_128_combinational dut(.crc(crc), .data(data), .out(out));
    end else begin : naive
      crc16_naive_128_combinational dut(.crc(crc), .data(data), .out(out));
    end
  endgenerate

  // Independent bit-serial reference, MSB first across the entire block.
  function automatic logic [15:0] reference_crc(
    input logic [15:0] initial_crc, input logic [127:0] block_data
  );
    logic [15:0] result;
    logic feedback;
    result = initial_crc;
    for (int bit_index = 127; bit_index >= 0; --bit_index) begin
      feedback = result[15] ^ block_data[bit_index];
      result = result << 1;
      if (feedback) result ^= 16'h1021;
    end
    return result;
  endfunction

  task automatic check_block;
    expected = reference_crc(crc, data);
    #1;
    if (out !== expected)
      $fatal(1, "crc=%h data=%h expected=%h actual=%h", crc, data, expected, out);
  endtask

  initial begin
    crc = 0;
    data = 0;
    check_block();
    crc = '1;
    data = '1;
    check_block();
    // Every input bit separately also checks bit and byte ordering.
    for (int i = 0; i < 144; ++i) begin
      {crc, data} = 144'b1 << i;
      check_block();
    end
    for (int i = 0; i < 1024; ++i) begin
      for (int j = 0; j < 4; ++j) begin
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        data[j*32 +: 32] = rng;
      end
      // Continue from the previous block's CRC to exercise block chaining.
      crc = expected;
      check_block();
    end
    $display("PASS: 1170 CRC-128 checks");
    $finish;
  end
endmodule

module crc16_optimized_128_testbench;
  crc16_naive_128_testbench #(.OPTIMIZED(1)) testbench();
endmodule
