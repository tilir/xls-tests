include_guard(DIRECTORY)

# Common RTL + synthesis registration. Timing applies only to pipeline codegen.
function(_crc_add_variant target source top generator)
  set(timing_args)
  if(generator STREQUAL "pipeline")
    list(APPEND timing_args CLOCK_PERIOD_PS "${CRC_CLOCK_PERIOD_PS}" DELAY_MODEL asap7)
  endif()
  xls_add_dslx(${target}
    SOURCE "${source}" TOP "${top}" GENERATOR "${generator}"
    ${timing_args} CODEGEN_ARGS "--module_name=${target}")
  add_yosys_synth(${target} RTL_TARGET ${target} TOP ${target})
endfunction()

# Pure functions: both generators by default, each with a signature-driven test.
# KIND tick checks the temporal transition's (next_crc, output_crc, valid) tuple.
function(crc_add_function name source top)
  cmake_parse_arguments(CRC "" "WIDTH;KIND" "GENERATORS" ${ARGN})
  if(NOT CRC_WIDTH)
    message(FATAL_ERROR "crc_add_function(${name}) requires WIDTH")
  endif()
  if(NOT CRC_KIND)
    set(CRC_KIND crc)
  endif()
  if(NOT CRC_GENERATORS)
    set(CRC_GENERATORS pipeline combinational)
  endif()
  foreach(generator IN LISTS CRC_GENERATORS)
    set(target "${name}_${generator}")
    _crc_add_variant(${target} "${source}" "${top}" "${generator}")
    if(BUILD_TESTING)
      get_property(signature TARGET ${target} PROPERTY XLS_SIGNATURE_OUTPUT)
      set(testbench "${CMAKE_CURRENT_BINARY_DIR}/${target}_testbench.sv")
      set(script "${CMAKE_SOURCE_DIR}/utils/generate_crc_function_test.rb")
      set(template "${CMAKE_CURRENT_SOURCE_DIR}/crc_function_testbench.sv.in")
      add_custom_command(
        OUTPUT "${testbench}"
        COMMAND "${RUBY_EXECUTABLE}" "${script}"
          --signature "${signature}" --output "${testbench}"
          --template "${template}" --width "${CRC_WIDTH}" --kind "${CRC_KIND}"
        DEPENDS "${signature}" "${script}" "${template}"
          "${CMAKE_SOURCE_DIR}/utils/xls_signature.rb"
        COMMENT "Generate ${target} test with XLS interface and latency"
        VERBATIM)
      xls_add_sv_test(${target}_test
        RTL_TARGET ${target} TOP crc_function_testbench SOURCES "${testbench}")
    endif()
  endforeach()
endfunction()

# Stateful procs: pipeline RTL, synthesis, and a channel protocol testbench.
function(crc_add_proc name source top)
  _crc_add_variant(${name} "${source}" "${top}" pipeline)
  if(BUILD_TESTING)
    xls_add_sv_test(${name}_test
      RTL_TARGET ${name}
      TOP ${name}_testbench
      WRAPPER_MODULE ${name}_test_dut
      SOURCES
        "${CMAKE_SOURCE_DIR}/utils/tb_util.sv"
        "${CMAKE_SOURCE_DIR}/utils/tb_watchdog.sv"
        "${name}_testbench.sv")
  endif()
endfunction()

# Compatibility names live here rather than complicating variant registration.
function(crc_alias alias target)
  if(TARGET ${target})
    add_custom_target(${alias})
    add_dependencies(${alias} ${target})
  endif()
endfunction()
