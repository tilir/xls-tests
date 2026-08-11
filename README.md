# XLS experiments

Each experiment has its own subdirectory and `CMakeLists.txt`. Register a new
experiment explicitly with `add_subdirectory(name)` in the root
`CMakeLists.txt`. Generated IR and SystemVerilog are written to the build tree.

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
  SOURCES
    "${CMAKE_SOURCE_DIR}/utils/tb_util.sv"
    "${CMAKE_SOURCE_DIR}/utils/tb_watchdog.sv"
    example_testbench.sv)
```
