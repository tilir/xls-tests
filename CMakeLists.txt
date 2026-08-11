cmake_minimum_required(VERSION 3.20)

project(xls_experiments LANGUAGES NONE)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
  message(FATAL_ERROR
    "In-source builds are disabled. Use: cmake -S . -B build")
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(Xls)
include(CTest)
include(SvTest)

if(BUILD_TESTING)
  add_custom_target(check
    COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
    COMMENT "Run SystemVerilog tests"
    USES_TERMINAL)
endif()

add_subdirectory(crc)
