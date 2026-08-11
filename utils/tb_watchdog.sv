// End a stalled testbench with a useful non-zero exit status.
module tb_watchdog #(
  parameter int unsigned MAX_CYCLES = 10000
) (
  input logic clock
);
  initial begin
    repeat (MAX_CYCLES) @(posedge clock);
    $fatal(1, "Testbench timeout after %0d cycles", MAX_CYCLES);
  end
endmodule
