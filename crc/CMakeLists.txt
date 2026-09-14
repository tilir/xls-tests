# Explicit scheduling budget for every pipeline (asap7 estimate, not STA).
set(CRC_CLOCK_PERIOD_PS "2000" CACHE STRING "CRC pipeline clock period in picoseconds")
if(NOT CRC_CLOCK_PERIOD_PS MATCHES "^[1-9][0-9]*$")
  message(FATAL_ERROR "CRC_CLOCK_PERIOD_PS must be a positive integer (picoseconds)")
endif()
include("${CMAKE_CURRENT_SOURCE_DIR}/Targets.cmake")

# Functions: each registration owns RTL, synthesis, and tests for both generators.
crc_add_function(crc16_function crc_function.x crc16_byte WIDTH 8)
crc_add_function(crc16_naive_128 crc_naive_128.x crc16_block WIDTH 128)
crc_add_function(crc16_optimized_128 crc_optimized_128.x crc16_block WIDTH 128)

# Procs require pipeline generation; temporal also exposes a pure transition.
crc_add_proc(crc16 crc_temporal.x Crc16)
crc_add_function(crc16_temporal crc_temporal.x crc16_tick
  WIDTH 8 KIND tick GENERATORS combinational)
crc_add_proc(crc16_sequential_128 crc_sequential_128.x Crc16Sequential128)

# Historical public names retained for existing build commands.
crc_alias(crc16_temporal_pipeline crc16)
crc_alias(synth_crc16_temporal_pipeline synth_crc16)
foreach(variant IN ITEMS naive optimized)
  foreach(suffix IN ITEMS sim verilator iverilog)
    crc_alias(crc16_${variant}_128_test_${suffix}
      crc16_${variant}_128_combinational_test_${suffix})
  endforeach()
endforeach()
