include_guard(GLOBAL)

set(XLS_ROOT "" CACHE PATH "Path to the XLS source tree built with Bazel")

function(_xls_find_tool variable relative_path program_name)
  set(hints)
  if(XLS_ROOT)
    list(APPEND hints "${XLS_ROOT}/bazel-bin/${relative_path}")
  endif()

  find_program(${variable}
    NAMES "${program_name}"
    HINTS ${hints}
    DOC "Path to the XLS ${program_name} executable")

  if(NOT ${variable})
    message(FATAL_ERROR
      "Could not find ${program_name}. Set XLS_ROOT to a built XLS checkout, "
      "or set ${variable} directly.")
  endif()

  set(${variable} "${${variable}}" PARENT_SCOPE)
endfunction()

_xls_find_tool(XLS_IR_CONVERTER
  "xls/dslx/ir_convert" "ir_converter_main")
_xls_find_tool(XLS_OPT_MAIN "xls/tools" "opt_main")
_xls_find_tool(XLS_CODEGEN_MAIN "xls/tools" "codegen_main")

# Adds one independently buildable DSLX entry point. Other .x files in the same
# directory are treated as sources/dependencies, so imports trigger a rebuild.
function(xls_add_dslx target)
  set(options)
  set(one_value_args SOURCE TOP OUTPUT_NAME GENERATOR DELAY_MODEL
                     CLOCK_PERIOD_PS RESET)
  set(multi_value_args CODEGEN_ARGS)
  cmake_parse_arguments(XLS "${options}" "${one_value_args}"
                        "${multi_value_args}" ${ARGN})

  if(NOT XLS_SOURCE OR NOT XLS_TOP)
    message(FATAL_ERROR "xls_add_dslx(${target}) requires SOURCE and TOP")
  endif()

  if(NOT XLS_OUTPUT_NAME)
    set(XLS_OUTPUT_NAME "${target}")
  endif()
  if(NOT XLS_GENERATOR)
    set(XLS_GENERATOR pipeline)
  endif()
  if(NOT XLS_DELAY_MODEL)
    set(XLS_DELAY_MODEL asap7)
  endif()
  if(NOT XLS_CLOCK_PERIOD_PS)
    set(XLS_CLOCK_PERIOD_PS 2000)
  endif()
  if(NOT XLS_RESET)
    set(XLS_RESET rst)
  endif()

  get_filename_component(source "${XLS_SOURCE}" ABSOLUTE
                         BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
  file(GLOB dslx_dependencies CONFIGURE_DEPENDS
       "${CMAKE_CURRENT_SOURCE_DIR}/*.x")

  set(output_dir "${CMAKE_CURRENT_BINARY_DIR}")
  set(ir "${output_dir}/${XLS_OUTPUT_NAME}.ir")
  set(opt_ir "${output_dir}/${XLS_OUTPUT_NAME}.opt.ir")
  set(verilog "${output_dir}/${XLS_OUTPUT_NAME}.sv")
  set(signature "${output_dir}/${XLS_OUTPUT_NAME}.signature.textproto")

  add_custom_command(
    OUTPUT "${ir}"
    COMMAND "${XLS_IR_CONVERTER}"
            "--top=${XLS_TOP}"
            "--dslx_path=${CMAKE_CURRENT_SOURCE_DIR}"
            "${source}"
            "--output_file=${ir}"
    DEPENDS ${dslx_dependencies}
    COMMENT "Converting ${XLS_SOURCE} to XLS IR"
    VERBATIM)

  add_custom_command(
    OUTPUT "${opt_ir}"
    COMMAND "${XLS_OPT_MAIN}" "${ir}" "--output_path=${opt_ir}"
    DEPENDS "${ir}"
    COMMENT "Optimizing ${XLS_OUTPUT_NAME}.ir"
    VERBATIM)

  add_custom_command(
    OUTPUT "${verilog}" "${signature}"
    COMMAND "${XLS_CODEGEN_MAIN}"
            "--generator=${XLS_GENERATOR}"
            "--delay_model=${XLS_DELAY_MODEL}"
            "--clock_period_ps=${XLS_CLOCK_PERIOD_PS}"
            "--reset=${XLS_RESET}"
            --use_system_verilog
            "--output_verilog_path=${verilog}"
            "--output_signature_path=${signature}"
            ${XLS_CODEGEN_ARGS}
            "${opt_ir}"
    DEPENDS "${opt_ir}"
    COMMENT "Generating ${XLS_OUTPUT_NAME}.sv"
    VERBATIM COMMAND_EXPAND_LISTS)

  add_custom_target("${target}" ALL DEPENDS "${verilog}")
  set_property(TARGET "${target}" PROPERTY XLS_VERILOG_OUTPUT "${verilog}")
  set_property(TARGET "${target}" PROPERTY XLS_SIGNATURE_OUTPUT "${signature}")
endfunction()
