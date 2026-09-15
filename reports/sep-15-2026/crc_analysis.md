# CRC16 XLS design-space analysis

## Executive summary

Seven RTL modules were generated from four DSLX sources. The examples expose three independent architectural decisions: temporal versus spatial execution, 16-bit folding versus full-block computation, and the algebraic form of the 128-bit CRC transformation.

XLS lowered the DSLX, eliminated unused folded state, generated ready/valid control, and scheduled pipeline registers from the target period. It did not transform the naive 128-bit recurrence into the shallow global XOR DAG written in crc_optimized.x: the naive combinational RTL still contains 128 feedback values and has generic depth 34, while the explicit DAG has depth 10.

Generic Yosys `synth -flatten` provides cell counts and structural netlists, but no technology mapping or static timing. A separate completed ORFS ASAP7 place-and-route run supplies physical metrics for the four clocked implementations at a real 1000 ps constraint. All four close setup timing.

## Artifacts and method

The supplied build1000 directory was configured at 1000 ps, but contained synthesis scripts without output reports. build2000 was absent. I regenerated both through the repository flow:

    cmake -S . -B build1000 -DXLS_ROOT=/home/tilir/xls -DCRC_CLOCK_PERIOD_PS=1000 -DBUILD_TESTING=OFF
    cmake --build build1000 --target synth -j 4
    cmake -S . -B build2000 -DXLS_ROOT=/home/tilir/xls -DCRC_CLOCK_PERIOD_PS=2000 -DBUILD_TESTING=OFF
    cmake --build build2000 --target synth -j 4

Recovered pipeline command lines use generator=pipeline, delay_model=asap7, clock_period_ps={1000|2000}, reset=rst, and SystemVerilog output. Function RTL visibly contains input and output flops; no explicit flop-option flag was passed. Combinational commands use generator=combinational and receive no timing argument. No throughput constraint was found; function signatures report II=1.

crc_metrics.csv is the machine-readable source for table values. Generic depth is a dependency-level maximum through the generic Yosys cell graph, treating sequential cells as boundaries. It explains structure, not delay. RTL caret operations is a textual ^ count, not a cell count.

[crc_yosys_cell_composition.png](crc_yosys_cell_composition.png) separates sequential and combinational generic-cell composition for representative architectures. [crc_compute_stages.png](crc_compute_stages.png) plots the compute-stage response of the two pipelined block functions. The stage plot deliberately excludes interface boundary registers: XLS signature latency remains in the table and its plot annotation. Regenerate both with `gnuplot crc_design_space.gnuplot` from this directory.

## Generated targets and architectures

| Source / entry point | Generated module | Generator | Interface and architecture |
| --- | --- | --- | --- |
| crc_naive.x / crc16_block | crc16_naive_128_{combinational,pipeline} | both | Pure crc[15:0], data[127:0] to out[15:0] full-block update |
| crc_optimized.x / crc16_block | crc16_optimized_128_{combinational,pipeline} | both | Same function interface; explicit shared XOR DAG |
| crc_folded.x / Crc16Folded128 | crc16_folded_128 | pipeline proc | 144-bit input and 16-bit output ready/valid channels; 16 CRC bits processed per cycle |
| crc_temporal.x / Crc16 | crc16 | pipeline proc | data,last byte stream with internal CRC state |
| crc_temporal.x / crc16_tick | crc16_temporal_combinational | combinational | crc plus data,last to next_crc, output_crc, valid |

The proc signature fields latency: 0 and initiation_interval: 1 describe XLS channel interfaces, not block completion latency.

### Naive spatial recurrence

The source loop iterates 128 CRC bits. Generated RTL no longer has explicit conditional branches: XOR algebra replaces the CRC conditional. It still resembles a long recurrence: the combinational RTL has 128 named feedback values, 270 assignments, and 384 caret tokens. Generic Yosys produces 385 cells and depth 34.

At 1000 ps, labels Pipe stage 0 through Pipe stage 4 represent an input boundary, four compute intervals, and an output boundary. Internal cuts carry 100, 60, and 20 bits. Their RTL names show 84 remaining data bits plus 16 feedback values, then 44+16, then 4+16. The recurrence is split 44, 40, 40, and 4 input bits: cuts follow live DAG state, not equal source-loop segments.

At 2000 ps, labels 0 through 2 give two compute intervals. The internal cut carries 41 remaining data bits plus 16 feedback bits, so the intervals cover 87 and 41 bits. Signature latency changes 5 to 3 cycles; II remains 1. Input and output register labels are not compute intervals.

### Explicit optimized XOR network

Generated crc_optimized.x RTL contains named x intermediates: 162 declarations and 438 caret tokens. This exposes sharing and a shallow DAG. It costs 438 generic cells versus the naive form's 385, but has depth 10 versus 34.

This is a depth-versus-logic tradeoff, not an area-optimization result: the explicit shared XOR DAG uses about 14% more generic combinational cells. At 1000 ps the naive network needs four compute stages, while this shallow DAG remains in one. The designer supplied the algebraic DAG; XLS then schedules the graph it receives.

Both timing targets generate the same pipeline: a 144-bit input register, one full-network compute interval, and a 16-bit output register. Signature latency is 2, and generic synthesis reports 160 flops plus the same 438 combinational cells as the combinational module. This is direct RTL evidence that expressing a better DAG changes what the scheduler can place between registers.

### Folded block engine

Declared DSLX state is data:128 + crc:16 + remaining:7 = 151 bits. Generated RTL holds reg [111:0] state data, 16 one-bit CRC registers, and reg [2:0] countdown: 131 physical state bits. XLS removed the lower 16 data bits, which are reconstructed as zero after the fixed left shift, and narrowed the countdown because only values 0 through 7 occur.

Each accepted processing cycle evaluates 16 feedback values and shifts data by 16. Input acceptance performs the first step and loads countdown 7; seven later accepted processing cycles finish the block. Thus no-stall block II is 8 cycles. Input ready is gated by idle, preventing overlap. On the final step, output backpressure holds the completion state rather than lose it. Generic synthesis reports 131 sequential and 224 combinational cells. Its storage is partly an interface consequence, rather than a directly comparable implementation cost against the byte stream: the engine accepts a complete 128-bit block, so it must retain the unprocessed remainder internally.

### Temporal byte stream

The stream proc has one 16-bit persistent CRC register. Non-final bytes can proceed every cycle; a final byte waits for output readiness. The output CRC includes the final byte, then the state is reset to zero. A 128-bit packet requires 16 accepted byte transfers without stalls. Generic synthesis reports 16 flops and 44 combinational cells.

The pure transition function removes stored state and ready/valid machinery. It retains eight byte feedback values and produces next_crc, output_crc, last. Its generic result is 42 combinational cells, compared with 60 total cells for the streaming proc.

The stream and folded measurements therefore answer different architectural questions. The stream receives bytes over time and retains only CRC state; the folded block interface receives all 128 bits at once and places the remaining transaction state inside the engine. Interface shape and state placement are design-space knobs too.

## Quantitative results

| Build | Target | Step bits | Block II | Signature latency | Compute intervals | Reg bits | Cells (seq/comb) | XOR/XNOR | Generic depth |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: | --- | ---: |
| 1000 / 2000 | naive combinational | 128 | N/A | N/A | 1 | 0 | 385 (0/385) | 67/317 | 34 |
| 1000 | naive pipeline | 128 | 1 | 5 | 4 | 340 | 730 (340/390) | 60/324 | N/A |
| 2000 | naive pipeline | 128 | 1 | 3 | 2 | 217 | 604 (217/387) | 63/321 | N/A |
| 1000 / 2000 | optimized combinational | 128 | N/A | N/A | 1 | 0 | 438 (0/438) | 62/376 | 10 |
| 1000 / 2000 | optimized pipeline | 128 | 1 | 2 | 1 | 160 | 598 (160/438) | 62/376 | N/A |
| 1000 / 2000 | folded proc | 16 | 8 | 0* | 8 | 131 | 355 (131/224) | 15/43 | 8 |
| 1000 / 2000 | temporal proc | 8 | 16 bytes | 0* | 16 byte steps | 16 | 60 (16/44) | 10/14 | 3 |
| 1000 / 2000 | temporal transition | 8 | N/A | N/A | 1 | 0 | 42 (0/42) | 9/15 | 4 |

* Proc interface latency is not completion latency. Combinational targets are duplicated in the CSV for both builds because they are generated in both directories but structurally identical.

## Timing target versus scheduling

Only the naive function changes across target periods. Tightening the same naive function from 2000 ps to 1000 ps changes the schedule from two to four CRC compute stages, raises generic sequential-cell count from 217 to 340, and changes signature latency from 3 to 5 cycles. The II stays 1. This is a changed generated microarchitecture, with higher register cost while the combinational cell count remains close at 387 versus 390.

Compute stages are combinational CRC intervals between register boundaries. They are distinct from XLS signature latency: the latter includes the function interface boundary stage(s), so the naive signatures report 3 and 5 cycles for two and four compute stages respectively. The optimized signatures remain 2 cycles because its single compute interval is unchanged.

The optimized DAG remains one compute interval at both targets. The two proc RTL modules are also bit-identical between the builds. This does not prove hardware timing at either period; it says the XLS scheduler made no different structural choice in these artifacts.

The Yosys scripts read Verilog, run hierarchy and synth -flatten, then write statistics and netlists. They do not load a standard-cell library, constrain a clock, run STA, place, or route. No report identifies a critical path or says whether folded control or CRC logic is timing-critical. Generic depths only explain why the naive recurrence is structurally deeper.

## ORFS ASAP7 physical implementation at 1 GHz

The four clocked RTL modules were placed and routed with OpenROAD-flow-scripts (ORFS) in `build1000`, using its ASAP7 platform at the default BC/NLDM corner. Each run constrained `clk` to 1000 ps, used a 60% requested core utilization, completed all flow stages, and emitted final netlists, DEF, GDS, SPEF, and STA reports under `build1000/crc/openroad/<target>/`. The final reports record zero flow errors and zero setup violations.

An earlier wrapper converted the repository's 1000 ps setting to SDC `-period 1.000`. ORFS interprets that value in picoseconds, so it was a 1 ps constraint rather than 1 ns; its negative-slack results are invalid and have been replaced. The fixed wrapper writes `create_clock -period 1000` and launches ORFS headlessly and serially.

| Module | Mapped instances | Std-cell area (µm²) | Utilization | Setup WNS (ps) | Setup TNS (ps) | Setup violations | Inferred critical period (ps) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `crc16` temporal proc | 274 | 16.461 | 73.79% | +838.248 | 0 | 0 | 161.752 |
| `crc16_folded_128` | 1,825 | 122.428 | 71.70% | +569.168 | 0 | 0 | 430.832 |
| `crc16_naive_128_pipeline` | 3,076 | 225.596 | 68.12% | +706.338 | 0 | 0 | 293.662 |
| `crc16_optimized_128_pipeline` | 2,080 | 154.431 | 69.78% | +746.235 | 0 | 0 | 253.765 |

The inferred critical period is `1000 ps - WNS`; it is included only as a direct reading aid for the 1 GHz constraint, not as a separately reported STA metric. The temporal byte engine is smallest and has the largest margin. The optimized 128-bit pipeline is 31.5% smaller than the naive one and has 39.9 ps more slack. ORFS's `finish__timing__fmax` field is inconsistent with the final WNS values, so it is deliberately omitted rather than interpreted as achieved frequency.

The worst paths are all register-to-register logic paths, not unbounded I/O paths. Temporal goes from CRC state bit 12 to state bit 5 through XOR/XNOR and final-state control (181.80 ps data arrival): its byte CRC/state update dominates. Folded goes from countdown state bit 1 to data state bit 6 through the step-completion compare/control and CRC-side logic (484.41 ps): state/control fanout dominates this worst path. Naive goes from `p0_feedback` to `p1_feedback` through the recursive XOR/XNOR feedback chain (355.99 ps), so it is CRC datapath. Optimized goes from an input pipeline register to the output register through its shared XOR DAG (308.06 ps), also CRC datapath.

### Closure conclusion

At the corrected physical target, every baseline already meets the prompt's closure criterion (`WNS >= 0`) with more than 500 ps margin. Therefore no compiler margin, extra pipeline registers, or DSLX sibling architecture is justified for a 1 GHz result: those changes would worsen area or latency without solving a real timing failure. `CRC_CLOCK_MARGIN_PERCENT` is available for a future tighter-target scheduling sweep and is passed only to XLS pipeline codegen; its default is 0. The attempted margin sweep is not reported as a physical tradeoff because its ORFS runs preceded the SDC-unit correction.

These ORFS runs are downstream physical implementations, not the XLS Bazel `place_and_route` rule described in AGENTS.md. Combinational function modules were not placed and routed because they have no clocked top-level wrapper or defined I/O timing constraints in this experiment.

## Functional consistency

The current repository test suite had previously passed 14 CTest entries: both simulators for the two 128-bit forms, the folded proc, temporal proc, and temporal transition. Function tests cover basis vectors, random data, chained CRC values, and reset with results in flight. Folded testing covers 302 blocks, reset, and output backpressure. Temporal testing covers 123456789, all 256 one-byte packets, output backpressure, and random packets.

For pure full-block forms, utils/compare_crc_netlists.rb propagates affine GF(2) expressions through generic XOR/XNOR/NOT/BUF netlists and compares all outputs. That is an exhaustive naive-versus-optimized equivalence check within the checker’s supported cell set. Proc tests are representative simulation, not a proof of every folded/temporal state and handshake trace.

## Conclusions for hardware engineers

This is evidence for a division of labor, not automatic architectural optimality. The designer chose the interface, state placement, temporal/spatial factor, folding factor, and algebraic graph. Those choices dominate the visible throughput/latency/logic tradeoffs. The naive and optimized forms compute the same transformation, but one favors generic cell count and the other depth.

XLS made alternatives inexpensive to express and evaluate: it lowered the CRC recurrence, removed provably constant folded state, generated channel protocol logic, scheduled one source function differently for two target periods, and inserted only live pipeline state at the corresponding cuts. It did not infer the manually supplied shallow global XOR DAG from the naive recurrence in these generated artifacts. ORFS technology mapping, placement, routing, and STA confirm that the baseline pipelines close at the corrected 1 GHz constraint; a tighter-frequency study is the next useful timing experiment.
