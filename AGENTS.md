# Development instructions

Keep README.md focused on user setup, target selection, interfaces, and commands.
Put implementation notes, development workflows, validation history, and
experimental measurements here. Update these notes when the implementation
changes; do not present old measurements as current guarantees.

Use Ruby for repository utilities. Keep the naive 128-bit DSLX implementation
self-contained: one function, one bit loop, no imports. Preserve existing public
build target names when reorganizing the build.

## Build organization

Each experiment has a directory and CMakeLists.txt. Register experiments with
`add_subdirectory` in the root CMakeLists.txt. Keep crc/CMakeLists.txt as a short
list of registrations and configuration; shared CRC rules live in
crc/Targets.cmake. Register RTL, synthesis, and tests together.

```cmake
crc_add_function(crc16_naive_128 crc_naive_128.x crc16_block WIDTH 128)
crc_add_proc(crc16_folded_128 crc_folded_128.x Crc16Folded128)
```

`crc_add_function` creates pipeline and combinational variants, their `synth_`
targets, and `<target>_test_sim` targets. `GENERATORS` restricts variants;
`KIND tick` selects the temporal transition's tuple output contract.
`crc_add_proc` creates pipeline RTL and uses `<name>_testbench.sv` with a generated
channel wrapper. Stateful procs cannot be lowered directly by the combinational
generator; the temporal combinational variant exposes a transition function.

Compatibility aliases are explicit at the end of crc/CMakeLists.txt. These
include `crc16_temporal_pipeline`, `synth_crc16_temporal_pipeline`, and old
`crc16_{naive,optimized}_128_test_{sim,verilator,iverilog}` names.

For other experiments, the underlying registration API is:

```cmake
xls_add_dslx(target_name
  SOURCE source_file.x
  TOP DslxTopName
  GENERATOR pipeline
  CLOCK_PERIOD_PS 2000
  DELAY_MODEL asap7
  OUTPUT_NAME generated_file_stem)
```

All .x files beside SOURCE are dependencies; they need not be independently
synthesizable. Additional code generator flags use CODEGEN_ARGS. Every CRC
pipeline explicitly receives the configured CRC_CLOCK_PERIOD_PS and the asap7
delay model. Combinational generation receives no clock-period, delay-model, or
reset flags. The scheduling period is not a Yosys timing constraint or an STA
result.

## Complete CRC build mapping

Keep this table synchronized with crc/CMakeLists.txt. Source paths below are
relative to crc/. Each row is a distinct RTL module; aliases do not create
additional implementations.

| DSLX source | Entry point | Generator | Build target / RTL module | Result |
| --- | --- | --- | --- | --- |
| `crc_naive_128.x` | `fn crc16_block` | `pipeline` | `crc16_naive_128_pipeline` | Pipelined 128-bit update from the naive loop |
| `crc_naive_128.x` | `fn crc16_block` | `combinational` | `crc16_naive_128_combinational` | Entire 128-bit update without registers |
| `crc_optimized_128.x` | `fn crc16_block` | `pipeline` | `crc16_optimized_128_pipeline` | Pipelined 128-bit update from the shared XOR network |
| `crc_optimized_128.x` | `fn crc16_block` | `combinational` | `crc16_optimized_128_combinational` | Shared 128-bit XOR network without registers |
| `crc_temporal.x` | `proc Crc16` | `pipeline` | `crc16` | Byte-stream channels, internal CRC accumulator, result and accumulator clear on `last` |
| `crc_temporal.x` | `fn crc16_tick` | `combinational` | `crc16_temporal_combinational` | `(crc, byte_input) -> (next_crc, output_crc, output_valid)`; caller owns state and handshake |
| `crc_folded_128.x` | `proc Crc16Folded128` | `pipeline` | `crc16_folded_128` | Channels accept initial CRC and 128-bit block; internal state processes 16 bits per step, then emits CRC |

For every canonical target `T` in the table:

| Artifact or action | Path / target / CTest name |
| --- | --- |
| Unoptimized IR | `build/crc/T.ir` |
| Optimized IR | `build/crc/T.opt.ir` |
| SystemVerilog | `build/crc/T.sv` (module name `T`) |
| XLS signature | `build/crc/T.signature.textproto` |
| Yosys synthesis target | `synth_T` |
| Synthesis artifacts | `build/crc/synth/T/` |
| Build all available simulators | `T_test_sim` |
| Build Verilator / Icarus image | `T_test_verilator` / `T_test_iverilog` |
| Run via CTest | `T_test.verilator` / `T_test.iverilog` |

Here `T` is a placeholder, not a literal filename. Synthesis targets require
Yosys; simulation targets require BUILD_TESTING and the corresponding installed
simulator. Pipeline latency comes from the signature and depends on
CRC_CLOCK_PERIOD_PS. A proc signature's pipeline latency does not describe its
whole packet/block processing time.

Compatibility aliases resolve as follows:

| Alias | Canonical target |
| --- | --- |
| `crc16_temporal_pipeline` | `crc16` |
| `synth_crc16_temporal_pipeline` | `synth_crc16` |
| `crc16_naive_128_test_sim` | `crc16_naive_128_combinational_test_sim` |
| `crc16_naive_128_test_verilator` | `crc16_naive_128_combinational_test_verilator` |
| `crc16_naive_128_test_iverilog` | `crc16_naive_128_combinational_test_iverilog` |
| `crc16_optimized_128_test_sim` | `crc16_optimized_128_combinational_test_sim` |
| `crc16_optimized_128_test_verilator` | `crc16_optimized_128_combinational_test_verilator` |
| `crc16_optimized_128_test_iverilog` | `crc16_optimized_128_combinational_test_iverilog` |

In particular, the temporal pipeline RTL is `build/crc/crc16.sv`, not
`build/crc/crc16_temporal_pipeline.sv`. There is no folded combinational
variant and no pipeline variant of `crc16_tick` in the current registrations.

## Tests

Function variants share crc/crc_function_testbench.sv.in.
utils/generate_crc_function_test.rb validates ports and reads pipeline latency
from the generated signature. Do not hardcode pipeline latency in testbenches.
The shared test issues an input every cycle, checks basis vectors, random inputs
and chained CRCs, and resets with results in flight. The temporal transition
also checks both values of last and the returned state.

Proc tests exercise reference CRCs, channel backpressure, and packet/block
handling; the folded test includes reset during processing. Channel wrappers
come from utils/generate_sv_wrapper.rb. Shared signature parsing helpers live in
utils/xls_signature.rb; CMake dependencies must include them when generating
wrappers or tests. Simulation adapters are excluded from synthesis.

To register a protocol test outside the CRC helpers:

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

WRAPPER_MODULE exposes stable `<channel>_data`, `<channel>_valid`, and
`<channel>_ready` ports. Shared scoreboard and watchdog utilities live in utils.

Validation recorded after the build refactor: nine RTL targets had tests in
both simulators, totaling 18 passing CTest entries at both 2000 and 1000 ps.
The naive pipeline latency changed from 3 to 5 cycles at the shorter period;
the signature-driven tests passed in both configurations. All synthesis targets
and representative compatibility aliases also built successfully. These counts
are historical, not constants to maintain in README.

## CRC implementation notes

The standalone byte-function experiment was removed: byte processing remains
inside crc_temporal.x, while the standalone function experiments process full
128-bit blocks. The shared function testbench still covers both block
implementations and the temporal transition. There are seven RTL variants.

The folded proc uses STEP_BITS=16, processing eight chunks per block. Its
initial CRC comes from the input transaction; it does not automatically carry
the result between blocks. const_assert checks in config require STEP_BITS to
be positive, smaller than 128, and a divisor of 128. Keep these checks: a
non-divisor truncates the block, while 128 would leave remaining at zero and
never trigger the existing send condition. Validation accepted 1, 4, 8, 16, 32,
and 64, and rejected 0, 3, 128, and 256 at compile time.

## XOR network generation and equivalence

crc/crc_optimized_128.x is generated; do not edit it manually. Regenerate with:

```sh
ruby utils/generate_crc128.rb
```

The generator propagates the CRC as linear GF(2) expressions, greedily shares
frequent XOR pairs, breaks ties by depth, and balances remaining expressions.
It is a heuristic, not a proof of global optimality.

Reproduce synthesis and check combinational equivalence with:

```sh
cmake --build build --target synth_crc16_naive_128_combinational synth_crc16_optimized_128_combinational
ruby utils/compare_crc_netlists.rb \
  build/crc/synth/crc16_naive_128_combinational/crc16_naive_128_combinational.json \
  build/crc/synth/crc16_optimized_128_combinational/crc16_optimized_128_combinational.json
```

The checker propagates exact affine expressions through XOR/XNOR/NOT/BUF cells,
compares all outputs, and rejects unsupported cells. Equality covers every
input combination, not just sampled vectors. The Ruby generator reproduced the
previous Python generator's DSLX except for its filename comment; the Ruby
checker matched successful, mismatched, and unsupported-cell cases.

## Recorded synthesis experiments

The common flow is Yosys `synth -flatten`. Measurements below are generic cell
counts and unit-gate depths, not physical area or technology-mapped delay.
Re-measure after relevant source or tool changes.

| Combinational 128-bit implementation | Cells | Maximum gate levels |
| --- | ---: | ---: |
| Naive loop | 385 | 34 |
| Shared XOR network | 438 | 10 |

The shared network traded about 14% more cells for lower depth.

Folded STEP_BITS sweep with asap7 scheduling at 2000 ps:

| Bits/step | Steps/block | Cells | Flip-flops | Gate levels between sequential boundaries |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 128 | 339 | 150 | 6 |
| 4 | 32 | 345 | 145 | 7 |
| 8 | 16 | 349 | 140 | 6 |
| 16 | 8 | 355 | 131 | 9 |
| 32 | 4 | 381 | 114 | 12 |
| 64 | 2 | 437 | 81 | 20 |

Selected 16 bits/step: half as many steps as the byte variant for six extra
cells and three extra gate levels. Counts include registers and control, so do
not compare them directly with the area of a bare combinational CRC function.

Synthesis artifacts include Verilog/JSON netlists, logs, and text/JSON statistics
under build/crc/synth/<target>/. Handwritten RTL can use the same flow:

```cmake
add_yosys_synth(crc16_handwritten
  TOP crc16_handwritten
  SOURCES crc16_handwritten.sv)
```
