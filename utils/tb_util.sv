// Shared scoreboard for self-checking SystemVerilog testbenches.
package tb_util_pkg;
  class scoreboard;
    int unsigned checks;
    int unsigned failures;
    int unsigned test_checks;
    int unsigned test_failures;
    bit verbose;

    function new;
      checks = 0;
      failures = 0;
      test_checks = 0;
      test_failures = 0;
      verbose = $test$plusargs("verbose");
    endfunction

    function void begin_test(input string name);
      test_checks = checks;
      test_failures = failures;
      $display("RUN  %s", name);
    endfunction

    function void end_test(input string name);
      int unsigned section_checks;
      int unsigned section_failures;
      section_checks = checks - test_checks;
      section_failures = failures - test_failures;
      if (section_failures == 0)
        $display("PASS %-24s %0d checks", name, section_checks);
      else
        $display("FAIL %-24s %0d of %0d checks", name,
                 section_failures, section_checks);
    endfunction

    function void check(input string name,
                        input logic [63:0] actual,
                        input logic [63:0] expected,
                        input int unsigned width,
                        input string details);
      logic [63:0] mask;
      mask = width == 64 ? '1 : (64'(1) << width) - 1;
      checks = checks + 1;
      if ((actual & mask) !== (expected & mask)) begin
        failures = failures + 1;
        $display("  FAIL %s: %s, actual=%0h expected=%0h",
                 name, details, actual & mask, expected & mask);
      end else if (verbose) begin
        $display("  ok   %s: %s, result=%0h",
                 name, details, actual & mask);
      end
    endfunction

    function void finish_tests(input string suite);
      $display("--------------------------------------------------");
      if (failures == 0) begin
        $display("PASS %s: %0d checks, no failures", suite, checks);
        $finish;
      end else begin
        $display("FAIL %s: %0d checks, %0d failures",
                 suite, checks, failures);
        $fatal(1, "%s tests failed", suite);
      end
    endfunction
  endclass

  scoreboard active_scoreboard;

  function void init_tests;
    active_scoreboard = new;
  endfunction

  function void begin_test(input string name);
    active_scoreboard.begin_test(name);
  endfunction

  function void end_test(input string name);
    active_scoreboard.end_test(name);
  endfunction

  function void check(input string name,
                      input logic [63:0] actual,
                      input logic [63:0] expected,
                      input int unsigned width,
                      input string details);
    active_scoreboard.check(name, actual, expected, width, details);
  endfunction

  function void finish_tests(input string suite);
    active_scoreboard.finish_tests(suite);
  endfunction
endpackage
