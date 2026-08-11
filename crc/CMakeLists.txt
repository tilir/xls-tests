xls_add_dslx(crc16
  SOURCE crc_temporal.x
  TOP Crc16
  OUTPUT_NAME crc16
  CODEGEN_ARGS --module_name=crc16)

add_yosys_synth(crc16
  RTL_TARGET crc16
  TOP crc16)

if(BUILD_TESTING)
  xls_add_sv_test(crc16_test
    RTL_TARGET crc16
    TOP crc16_testbench
    SOURCES
      "${CMAKE_SOURCE_DIR}/utils/tb_util.sv"
      "${CMAKE_SOURCE_DIR}/utils/tb_watchdog.sv"
      crc16_testbench.sv)
endif()
