# Standalone DSLX property/proof lesson. It deliberately has no RTL, Yosys,
# or ORFS registration: the tools interpret and prove the source directly.
set(formal_source "${CMAKE_CURRENT_SOURCE_DIR}/crc_formal.x")
set(formal_tool_hint "${XLS_ROOT}/bazel-bin/xls/dslx")
find_program(XLS_DSLX_INTERPRETER NAMES interpreter_main HINTS "${formal_tool_hint}")
find_program(XLS_PROVE_QUICKCHECK NAMES prove_quickcheck_main HINTS "${formal_tool_hint}")

if(NOT XLS_DSLX_INTERPRETER OR NOT XLS_PROVE_QUICKCHECK)
  message(STATUS
    "Formal CRC targets are disabled: build //xls/dslx:interpreter_main and "
    "//xls/dslx:prove_quickcheck_main in XLS_ROOT")
  return()
endif()

add_custom_target(formal_crc_concrete
  COMMAND "${XLS_DSLX_INTERPRETER}" --compare=jit
    "--test_filter=(test_crc16_123456789|prop_reverse_u8_involution|prop_xor_u4_exhaustive)"
    "${formal_source}"
  DEPENDS "${formal_source}"
  COMMENT "Run CRC formal lesson unit tests and concrete QuickChecks"
  VERBATIM)

foreach(property IN ITEMS
    prop_crc16_matches_polynomial
    prop_crc16_linear
    prop_crc16_composes_64_64)
  add_custom_target("formal_crc_${property}"
    COMMAND "${XLS_PROVE_QUICKCHECK}" "--test_filter=${property}" "${formal_source}"
    DEPENDS "${formal_source}"
    COMMENT "Prove ${property} with XLS SMT"
    VERBATIM)
endforeach()

add_custom_target(formal_crc
  DEPENDS formal_crc_concrete
    formal_crc_prop_crc16_matches_polynomial
    formal_crc_prop_crc16_linear
    formal_crc_prop_crc16_composes_64_64)

# This is intentionally an error target: its SMT counterexample is the lesson.
add_custom_target(formal_crc_false
  COMMAND "${XLS_PROVE_QUICKCHECK}"
    "--test_filter=prop_crc16_false_ignores_initial_state" "${formal_source}"
  DEPENDS "${formal_source}"
  COMMENT "Demonstrate a failing CRC SMT property (expected to fail)"
  VERBATIM)

# Mathematically false by pigeonhole principle, but finding a counterexample
# is intended to be computationally infeasible. Never add it to formal_crc.
set(sha256_collision_source "${CMAKE_CURRENT_SOURCE_DIR}/sha256_collision_hard.x")
add_custom_target(formal_sha256_collision_hard
  COMMAND "${XLS_PROVE_QUICKCHECK}"
    "--dslx_path=${XLS_ROOT}/xls/examples"
    "--test_filter=prop_sha256_compression_is_injective" "${sha256_collision_source}"
  DEPENDS "${sha256_collision_source}"
  COMMENT "Attempt an infeasible SHA-256 compression collision proof"
  VERBATIM)
