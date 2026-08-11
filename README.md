# XLS experiments

Each experiment has its own subdirectory and `CMakeLists.txt`. Register a new
experiment explicitly with `add_subdirectory(name)` in the root
`CMakeLists.txt`. Generated IR, SystemVerilog, and the XLS module signature are
written to the build tree.

Configure and build everything:

```sh
cmake -S . -B build -DXLS_ROOT=/path/to/xls
cmake --build build
cmake --build build --target check
```

Build only the CRC entry point:

```sh
cmake --build build --target crc16
```

To add an entry point (including another one in the same experiment), add this
to that experiment's `CMakeLists.txt`:

```cmake
xls_add_dslx(target_name
  SOURCE source_file.x
  TOP DslxTopName
  OUTPUT_NAME generated_file_stem)
```

All `.x` files beside `SOURCE` are dependencies. Thus helper/imported DSLX
files cause a rebuild, but are not assumed to be independently synthesizable.
Extra code generator flags can be passed with `CODEGEN_ARGS`.

## SystemVerilog tests

Tests are enabled by default and run with both Verilator and Icarus Verilog
when those tools are available. `check` builds every simulation image and runs
the registered CTest suites. Individual tests can also be run with:

```sh
ctest --test-dir build --output-on-failure
```

Reusable scoreboard and watchdog components live in `utils`. Add a testbench
for generated RTL with:

```cmake
xls_add_sv_test(example_test
  RTL_TARGET example
  TOP example_testbench
  WRAPPER_MODULE example_test_dut
  SOURCES
    "${CMAKE_SOURCE_DIR}/utils/tb_util.sv"
    "${CMAKE_SOURCE_DIR}/utils/tb_watchdog.sv"
    example_testbench.sv)
```

`WRAPPER_MODULE` generates a simulation-only adapter from the XLS module
signature. Testbenches use stable `<channel>_data`, `<channel>_valid`, and
`<channel>_ready` ports instead of depending on XLS-generated port names. The
adapter is not included in Yosys synthesis.

## Yosys synthesis

When Yosys is available, synthesize all registered implementations or only the
generated CRC module with:

```sh
cmake --build build --target synth
cmake --build build --target synth_crc16
```

Artifacts are written under `build/crc/synth/crc16/`: the structural Verilog
and JSON netlists, a complete Yosys log, and statistics in human-readable and
JSON formats. The flow uses `synth -flatten` so independently registered
implementations can be compared consistently.

Handwritten RTL can use the same synthesis flow:

```cmake
add_yosys_synth(crc16_handwritten
  TOP crc16_handwritten
  SOURCES crc16_handwritten.sv)
```
