# XLS experiments

CRC hardware experiments written in DSLX, with SystemVerilog generation,
simulation, and Yosys synthesis.

## Build

Requires CMake and an XLS checkout with `ir_converter_main`, `opt_main`, and
`codegen_main` built. Tests use Verilator and/or Icarus Verilog plus Ruby;
Yosys is optional for synthesis.

```sh
cmake -S . -B build -DXLS_ROOT=/path/to/xls -DCRC_CLOCK_PERIOD_PS=2000
cmake --build build
cmake --build build --target check
```

`CRC_CLOCK_PERIOD_PS` sets the scheduling period for CRC pipeline targets in
picoseconds: a positive integer, default `2000` (2 ns, 500 MHz). Changing it can
change pipeline latency. It does not affect combinational targets and is not a
physical timing guarantee.

Generated IR, SystemVerilog, and module signatures are under `build/crc/`.
Configure with `-DBUILD_TESTING=OFF` to build without simulation tests.

## CRC targets

| Target | Operation |
| --- | --- |
| `crc16_naive_128_pipeline` | 128-bit block, pipelined |
| `crc16_naive_128_combinational` | 128-bit block, combinational |
| `crc16_optimized_128_pipeline` | 128-bit block using an optimized XOR network, pipelined |
| `crc16_optimized_128_combinational` | Same XOR network, combinational |
| `crc16_folded_128` | 128-bit block through ready/valid channels, 16 bits per processing step |
| `crc16_temporal_pipeline` (alias `crc16`) | Byte stream with internal CRC state and packet boundaries |
| `crc16_temporal_combinational` | One byte-stream state transition, with external state |

Build individual variants with:

```sh
cmake --build build --target crc16_naive_128_pipeline crc16_naive_128_combinational
```

All variants compute CRC16 with polynomial `0x1021`, processing the most
significant bit first. For 128-bit blocks, the most significant byte comes first.

The function variants take an initial CRC and data, and return the updated CRC.
Use zero for a new message; pass the previous result to continue it. Pipeline
latency is recorded in each generated `.signature.textproto` file.

`crc16_folded_128` accepts `{crc: u16, data: uN[128]}` and returns a CRC16
through ready/valid channels. It processes one block in eight steps; stalls can
extend that time. Reset discards the current block.

`crc16_temporal_pipeline` accepts `{data: u8, last: bool}`. It accumulates CRC
from zero, emits a result when `last` is set, and starts the next packet from
zero. `crc16_temporal_combinational` instead takes `(crc, byte_input)` and returns
`(next_crc, output_crc, output_valid)`; the caller supplies state storage and
handshake logic.

## Tests and synthesis

Run all tests with `cmake --build build --target check`. To build and run one
function variant's tests:

```sh
cmake --build build --target crc16_naive_128_pipeline_test_sim
ctest --test-dir build -R crc16_naive_128_pipeline_test --output-on-failure
```

When Yosys is installed, build `synth` for all variants or `synth_<target>` for
one variant:

```sh
cmake --build build --target synth
cmake --build build --target synth_crc16_naive_128_pipeline
```

Netlists, logs, and statistics are under `build/crc/synth/<target>/`.
