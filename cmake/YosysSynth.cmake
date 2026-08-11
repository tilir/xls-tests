include_guard(GLOBAL)

find_program(YOSYS_EXECUTABLE yosys)

if(YOSYS_EXECUTABLE)
  message(STATUS "Yosys synthesis: ${YOSYS_EXECUTABLE}")
  if(NOT TARGET synth)
    add_custom_target(synth)
  endif()
else()
  message(STATUS "Yosys not found; synthesis targets are disabled")
endif()

# Synthesize generated or handwritten SystemVerilog with a common flow.
# RTL_TARGET may name an xls_add_dslx target; SOURCES may contain ordinary RTL.
function(add_yosys_synth name)
  if(NOT YOSYS_EXECUTABLE)
    return()
  endif()

  set(options)
  set(one_value_args TOP RTL_TARGET)
  set(multi_value_args SOURCES)
  cmake_parse_arguments(YS "${options}" "${one_value_args}"
                        "${multi_value_args}" ${ARGN})

  if(NOT YS_TOP)
    message(FATAL_ERROR "add_yosys_synth(${name}) requires TOP")
  endif()
  if(NOT YS_RTL_TARGET AND NOT YS_SOURCES)
    message(FATAL_ERROR
      "add_yosys_synth(${name}) requires RTL_TARGET or SOURCES")
  endif()

  set(sources)
  set(dependencies)
  if(YS_RTL_TARGET)
    if(NOT TARGET "${YS_RTL_TARGET}")
      message(FATAL_ERROR
        "add_yosys_synth(${name}): unknown target ${YS_RTL_TARGET}")
    endif()
    get_property(generated_rtl TARGET "${YS_RTL_TARGET}"
                 PROPERTY XLS_VERILOG_OUTPUT)
    if(NOT generated_rtl)
      message(FATAL_ERROR
        "Target ${YS_RTL_TARGET} has no generated SystemVerilog output")
    endif()
    list(APPEND sources "${generated_rtl}")
    list(APPEND dependencies "${YS_RTL_TARGET}")
  endif()

  foreach(source IN LISTS YS_SOURCES)
    get_filename_component(source_abs "${source}" ABSOLUTE
                           BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    list(APPEND sources "${source_abs}")
  endforeach()
  list(APPEND dependencies ${sources})

  set(output_dir "${CMAKE_CURRENT_BINARY_DIR}/synth/${name}")
  set(script "${output_dir}/${name}.ys")
  set(netlist_json "${output_dir}/${name}.json")
  set(netlist_verilog "${output_dir}/${name}.v")
  set(stats_json "${output_dir}/${name}.stats.json")
  set(stats_text "${output_dir}/${name}.stats.txt")
  set(log "${output_dir}/${name}.log")

  set(read_commands)
  foreach(source IN LISTS sources)
    string(APPEND read_commands
      "read_verilog -sv -DSYNTHESIS \"${source}\"\n")
  endforeach()

  file(GENERATE OUTPUT "${script}" CONTENT
"${read_commands}hierarchy -check -top ${YS_TOP}
synth -top ${YS_TOP} -flatten
tee -o \"${stats_text}\" stat -top ${YS_TOP}
tee -o \"${stats_json}\" stat -json -top ${YS_TOP}
write_json \"${netlist_json}\"
write_verilog -noattr \"${netlist_verilog}\"
")

  add_custom_command(
    OUTPUT "${netlist_json}" "${netlist_verilog}"
           "${stats_json}" "${stats_text}" "${log}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${output_dir}"
    COMMAND "${YOSYS_EXECUTABLE}" -q -l "${log}" "${script}"
    DEPENDS ${dependencies} "${script}"
    COMMENT "Synthesize ${YS_TOP} with Yosys"
    VERBATIM COMMAND_EXPAND_LISTS)

  add_custom_target("synth_${name}"
    DEPENDS "${netlist_json}" "${netlist_verilog}"
            "${stats_json}" "${stats_text}" "${log}")
  add_dependencies(synth "synth_${name}")
endfunction()
