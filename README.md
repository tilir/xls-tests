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

CRC implementations (each target produces separate IR, RTL, and signature files):

| Target | DSLX top | Generator |
| --- | --- | --- |
| `crc16_function_pipeline` | `crc_function.x:crc16_byte` | pipeline |
| `crc16_function_combinational` | `crc_function.x:crc16_byte` | combinational |
| `crc16_naive_128_combinational` | `crc_naive_128.x:crc16_block` | combinational |
| `crc16_optimized_128_combinational` | `crc_optimized_128.x:crc16_block` | combinational |
| `crc16_sequential_128` | `crc_sequential_128.x:Crc16Sequential128` | pipeline (stateful proc) |
| `crc16_temporal_pipeline` (alias for `crc16`) | `crc_temporal.x:Crc16` | pipeline |
| `crc16_temporal_combinational` | `crc_temporal.x:crc16_tick` | combinational |

```sh
cmake --build build --target crc16_function_pipeline crc16_function_combinational
cmake --build build --target crc16_temporal_pipeline crc16_temporal_combinational
```

The pure function takes `(crc: u16, data: u8)` and returns the updated CRC,
with an eight-step loop unrolled by the compiler, matching the temporal implementation.
Start with zero and feed the returned CRC into the next byte update.

The naive 128-bit variant takes `(crc: u16, data: uN[128])` and returns a
16-bit CRC for the entire block. A single loop processes all 128 bits from
`data[127]` down to `data[0]`, with the bit update written inline and no imports.
There are no internal registers or clock ports: a caller can place it between
registers for a single-cycle update, subject to meeting the desired clock period.
Build it with `cmake --build build --target crc16_naive_128_combinational`.

The optimized 128-bit variant has the same interface and bit order. It expresses
the CRC as a linear XOR network, sharing frequent pairs and balancing remaining
output expressions. Regenerate its standalone DSLX with
`ruby utils/generate_crc128.rb`. This is a heuristic, not a globally optimal
circuit. Under the current common Yosys `synth -flatten` flow:

| 128-bit implementation | Generic cells | Maximum gate levels |
| --- | ---: | ---: |
| Naive loop | 385 | 34 |
| Shared XOR network | 438 | 10 |

The network trades about 14% more cells for fewer logic levels. These are generic
gate counts and unit-gate depths, not physical area or technology-mapped timing.
Both variants run the same 1170 reference checks in the registered SV tests.
To reproduce synthesis and prove equality for all input CRC/data combinations:

```sh
cmake --build build --target synth_crc16_naive_128_combinational synth_crc16_optimized_128_combinational
ruby utils/compare_crc_netlists.rb \
  build/crc/synth/crc16_naive_128_combinational/crc16_naive_128_combinational.json \
  build/crc/synth/crc16_optimized_128_combinational/crc16_optimized_128_combinational.json
```

The checker propagates exact affine GF(2) expressions through XOR/XNOR/NOT
cells and compares every output, rejecting unsupported cell types.

The sequential 128-bit variant reuses a 16-bit CRC update circuit across eight
processing steps. Its ready/valid input carries `{crc: u16, data: uN[128]}`
(packed as `{crc, data}` in RTL); its ready/valid output carries the final CRC16.
Use zero for a new packet or the previous result to chain blocks. Bits are
processed MSB first. Only one block is processed at a time; input backpressure
holds the next block, and output backpressure holds the completed result.
Reset discards an in-flight block. Channel buffering/handshakes can add latency
beyond the eight processing steps.

```sh
cmake --build build --target crc16_sequential_128 synth_crc16_sequential_128
```

A sweep of `STEP_BITS` with the same pipeline settings (`asap7`, 2000 ps) and
Yosys flow gave the following generic netlist measurements. Cells include
registers and control, so these totals are not directly comparable to a bare
combinational CRC function's area.

| Bits/step | Processing steps/block | Total cells | Flip-flops | Gate levels between sequential boundaries |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 128 | 339 | 150 | 6 |
| 4 | 32 | 345 | 145 | 7 |
| 8 | 16 | 349 | 140 | 6 |
| **16** | **8** | **355** | **131** | **9** |
| 32 | 4 | 381 | 114 | 12 |
| 64 | 2 | 437 | 81 | 20 |

The selected 16-bit step halves the processing steps relative to 8 bits for
six extra generic cells, at the cost of three more gate levels. This is a
size/throughput/depth compromise, not a global or technology-specific optimum.
The sequential tests cover reference CRCs, block chaining, queued input,
output backpressure, and reset during processing in both simulators.

XLS cannot generate combinational RTL directly from a stateful proc. The
combinational temporal target therefore exposes the proc's transition function:
`(crc, byte_input) -> (next_crc, output_crc, output_valid)`. `byte_input` contains
`data` and `last`; `last` asserts `output_valid` and clears `next_crc`. The caller
must store the state and provide any handshake logic. The pipeline proc retains
its channels, internal accumulator, and backpressure support.

Each implementation also has a `synth_<target>` target; the temporal pipeline
uses the existing `synth_crc16` name.

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
Select `GENERATOR pipeline` (default) or `GENERATOR combinational`. Clock,
delay-model, and reset flags apply only to pipeline generation. Extra code
generator flags can be passed with `CODEGEN_ARGS`.

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
