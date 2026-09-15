include_guard(GLOBAL)
set(ORFS_ROOT "$ENV{HOME}/OpenROAD-flow-scripts" CACHE PATH "Path to ORFS")
if(NOT EXISTS "${ORFS_ROOT}/flow/Makefile")
  message(STATUS "ORFS physical targets are disabled: set ORFS_ROOT to an OpenROAD-flow-scripts checkout")
  set(ORFS_AVAILABLE FALSE)
else()
  set(ORFS_AVAILABLE TRUE)
endif()
function(orfs_add_pnr name)
  if(NOT ORFS_AVAILABLE)
    return()
  endif()
  cmake_parse_arguments(ORFS "" "RTL_TARGET;TOP;CLOCK_PERIOD_PS" "" ${ARGN})
  get_property(rtl TARGET "${ORFS_RTL_TARGET}" PROPERTY XLS_VERILOG_OUTPUT)
  set(run_dir "${CMAKE_CURRENT_BINARY_DIR}/openroad/${name}")
  set(result "${run_dir}/results/asap7/${name}/base/6_final.v")
  add_custom_command(OUTPUT "${result}"
    COMMAND "${RUBY_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/utils/generate_orfs_config.rb"
      --output "${run_dir}" --rtl "${rtl}" --top "${ORFS_TOP}" --period-ps "${ORFS_CLOCK_PERIOD_PS}"
    # ORFS final reporting optionally invokes OpenROAD's GUI to render images.
    # Force headless operation so an inherited stale DISPLAY cannot abort P&R.
    COMMAND "${CMAKE_COMMAND}" -E env "DISPLAY=" "${CMAKE_MAKE_PROGRAM}" -j1 -C "${ORFS_ROOT}/flow"
      "DESIGN_CONFIG=${run_dir}/config.mk" "WORK_HOME=${run_dir}" all
    DEPENDS "${rtl}" "${CMAKE_SOURCE_DIR}/utils/generate_orfs_config.rb"
    COMMENT "Place and route ${name} with ORFS ASAP7" VERBATIM)
  add_custom_target("openroad_${name}" DEPENDS "${result}")
  if(NOT TARGET openroad)
    add_custom_target(openroad)
  endif()
  add_dependencies(openroad "openroad_${name}")
endfunction()
