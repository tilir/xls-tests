include_guard(GLOBAL)

find_program(VERILATOR_EXECUTABLE verilator)
find_program(IVERILOG_EXECUTABLE iverilog)
find_program(VVP_EXECUTABLE vvp)

if(VERILATOR_EXECUTABLE)
  message(STATUS "Verilator tests: ${VERILATOR_EXECUTABLE}")
else()
  message(STATUS "Verilator not found; Verilator tests are disabled")
endif()

if(IVERILOG_EXECUTABLE AND VVP_EXECUTABLE)
  message(STATUS "Icarus Verilog tests: ${IVERILOG_EXECUTABLE}")
else()
  message(STATUS "Icarus Verilog or vvp not found; Icarus tests are disabled")
endif()

# Compile and register a self-checking SV testbench against generated XLS RTL.
function(xls_add_sv_test name)
  set(options)
  set(one_value_args RTL_TARGET TOP)
  set(multi_value_args SOURCES)
  cmake_parse_arguments(SV "${options}" "${one_value_args}"
                        "${multi_value_args}" ${ARGN})

  if(NOT SV_RTL_TARGET OR NOT SV_TOP OR NOT SV_SOURCES)
    message(FATAL_ERROR
      "xls_add_sv_test(${name}) requires RTL_TARGET, TOP, and SOURCES")
  endif()
  if(NOT TARGET "${SV_RTL_TARGET}")
    message(FATAL_ERROR
      "xls_add_sv_test(${name}): unknown RTL target ${SV_RTL_TARGET}")
  endif()

  get_property(rtl TARGET "${SV_RTL_TARGET}" PROPERTY XLS_VERILOG_OUTPUT)
  if(NOT rtl)
    message(FATAL_ERROR
      "Target ${SV_RTL_TARGET} has no generated SystemVerilog output")
  endif()

  set(sources)
  foreach(source IN LISTS SV_SOURCES)
    get_filename_component(source_abs "${source}" ABSOLUTE
                           BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    list(APPEND sources "${source_abs}")
  endforeach()

  set(sim_targets)

  if(VERILATOR_EXECUTABLE)
    set(verilator_dir "${CMAKE_CURRENT_BINARY_DIR}/${name}_verilator_dir")
    set(verilator_binary "${verilator_dir}/${name}")
    add_custom_command(
      OUTPUT "${verilator_binary}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${verilator_dir}"
      COMMAND "${VERILATOR_EXECUTABLE}"
              --binary --timing --trace-fst
              -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-TIMESCALEMOD
              -Wno-WIDTHEXPAND
              --top-module "${SV_TOP}"
              --Mdir "${verilator_dir}" -o "${name}"
              ${sources} "${rtl}"
      DEPENDS ${sources} "${rtl}" "${SV_RTL_TARGET}"
      COMMENT "Compile ${name} with Verilator"
      VERBATIM COMMAND_EXPAND_LISTS)
    add_custom_target("${name}_verilator" DEPENDS "${verilator_binary}")
    add_test(NAME "${name}.verilator" COMMAND "${verilator_binary}")
    set_tests_properties("${name}.verilator" PROPERTIES
      WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
      TIMEOUT 30)
    list(APPEND sim_targets "${name}_verilator")
  endif()

  if(IVERILOG_EXECUTABLE AND VVP_EXECUTABLE)
    set(iverilog_image "${CMAKE_CURRENT_BINARY_DIR}/${name}.vvp")
    add_custom_command(
      OUTPUT "${iverilog_image}"
      COMMAND "${IVERILOG_EXECUTABLE}" -g2012 -s "${SV_TOP}"
              -o "${iverilog_image}" ${sources} "${rtl}"
      DEPENDS ${sources} "${rtl}" "${SV_RTL_TARGET}"
      COMMENT "Compile ${name} with Icarus Verilog"
      VERBATIM COMMAND_EXPAND_LISTS)
    add_custom_target("${name}_iverilog" DEPENDS "${iverilog_image}")
    add_test(NAME "${name}.iverilog"
      COMMAND "${VVP_EXECUTABLE}" "${iverilog_image}")
    set_tests_properties("${name}.iverilog" PROPERTIES
      WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
      TIMEOUT 30)
    list(APPEND sim_targets "${name}_iverilog")
  endif()

  if(sim_targets)
    add_custom_target("${name}_sim" ALL DEPENDS ${sim_targets})
    add_dependencies(check "${name}_sim")
  else()
    message(WARNING "No simulator found; test ${name} is disabled")
  endif()
endfunction()
