xls_add_dslx(crc16
  SOURCE crc_temporal.x
  TOP Crc16
  OUTPUT_NAME crc16
  GENERATOR pipeline
  CODEGEN_ARGS --module_name=crc16)

add_yosys_synth(crc16
  RTL_TARGET crc16
  TOP crc16)

if(BUILD_TESTING)
  xls_add_sv_test(crc16_test
    RTL_TARGET crc16
    TOP crc16_testbench
    WRAPPER_MODULE crc16_test_dut
    SOURCES
      "${CMAKE_SOURCE_DIR}/utils/tb_util.sv"
      "${CMAKE_SOURCE_DIR}/utils/tb_watchdog.sv"
      crc16_testbench.sv)
endif()

# Preserve crc16 as the existing streaming pipeline target.
add_custom_target(crc16_temporal_pipeline DEPENDS crc16)

xls_add_dslx(crc16_temporal_combinational
  SOURCE crc_temporal.x
  TOP crc16_tick
  GENERATOR combinational
  CODEGEN_ARGS --module_name=crc16_temporal_combinational)
add_yosys_synth(crc16_temporal_combinational
  RTL_TARGET crc16_temporal_combinational
  TOP crc16_temporal_combinational)

foreach(generator IN ITEMS pipeline combinational)
  set(target crc16_function_${generator})
  xls_add_dslx(${target}
    SOURCE crc_function.x
    TOP crc16_byte
    GENERATOR ${generator}
    CODEGEN_ARGS --module_name=${target})
  add_yosys_synth(${target} RTL_TARGET ${target} TOP ${target})
endforeach()

xls_add_dslx(crc16_naive_128_combinational
  SOURCE crc_naive_128.x
  TOP crc16_block
  GENERATOR combinational
  CODEGEN_ARGS --module_name=crc16_naive_128_combinational)
add_yosys_synth(crc16_naive_128_combinational
  RTL_TARGET crc16_naive_128_combinational
  TOP crc16_naive_128_combinational)

if(BUILD_TESTING)
  xls_add_sv_test(crc16_naive_128_test
    RTL_TARGET crc16_naive_128_combinational
    TOP crc16_naive_128_testbench
    SOURCES crc16_naive_128_testbench.sv)
endif()

xls_add_dslx(crc16_optimized_128_combinational
  SOURCE crc_optimized_128.x
  TOP crc16_block
  GENERATOR combinational
  CODEGEN_ARGS --module_name=crc16_optimized_128_combinational)
add_yosys_synth(crc16_optimized_128_combinational
  RTL_TARGET crc16_optimized_128_combinational
  TOP crc16_optimized_128_combinational)

if(BUILD_TESTING)
  xls_add_sv_test(crc16_optimized_128_test
    RTL_TARGET crc16_optimized_128_combinational
    TOP crc16_optimized_128_testbench
    SOURCES crc16_naive_128_testbench.sv)
endif()

xls_add_dslx(crc16_sequential_128
  SOURCE crc_sequential_128.x
  TOP Crc16Sequential128
  GENERATOR pipeline
  CODEGEN_ARGS --module_name=crc16_sequential_128)
add_yosys_synth(crc16_sequential_128
  RTL_TARGET crc16_sequential_128
  TOP crc16_sequential_128)

if(BUILD_TESTING)
  xls_add_sv_test(crc16_sequential_128_test
    RTL_TARGET crc16_sequential_128
    TOP crc16_sequential_128_testbench
    WRAPPER_MODULE crc16_sequential_128_test_dut
    SOURCES
      "${CMAKE_SOURCE_DIR}/utils/tb_watchdog.sv"
      crc16_sequential_128_testbench.sv)
endif()
