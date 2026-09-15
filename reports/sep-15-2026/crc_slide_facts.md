# CRC/XLS slide facts

- Tightening only `--clock_period_ps` from 2000 ps to 1000 ps changes the same `crc_naive.x` function from 2 to 4 compute stages and 217 to 340 generic sequential cells. II remains 1; signature latency changes from 3 to 5 cycles.
- The explicit shared XOR DAG stays at one compute stage at both periods: 160 generic sequential cells and signature latency 2.
- Full-block combinational forms: naive recurrence = 385 generic cells and depth 34; shallow shared XOR DAG = 438 cells and depth 10. The DAG trades about 14% more generic logic for much lower structural depth.
- `crc16_folded_128` processes 16 bits per step and completes a 128-bit block in 8 accepted processing cycles. It has 131 sequential and 224 combinational generic cells; accepting the whole block requires storing its unprocessed remainder.
- XLS reduced folded declared state from 151 bits (`128 + 16 + 7`) to 131 physical bits: 112 data, 16 CRC, and a 3-bit countdown.
- The temporal stream has 16 persistent CRC cells and 44 combinational cells, and accepts one byte per cycle when flow control permits. A 128-bit packet is 16 accepted byte transactions.
- Stream and folded results have different interface shapes and state placement; their 60-versus-355 generic-cell totals are not a direct quality ranking.
- Values come from generic Yosys `synth -flatten`, with no technology library, STA, area, slack, critical-delay, or achieved-Fmax result.
