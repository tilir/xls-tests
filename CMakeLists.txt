cmake_minimum_required(VERSION 3.20)

project(xls_experiments LANGUAGES NONE)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
  message(FATAL_ERROR
    "In-source builds are disabled. Use: cmake -S . -B build")
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(Xls)

add_subdirectory(crc)
