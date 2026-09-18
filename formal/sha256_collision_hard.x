// Deliberately infeasible formal counterexample search.
//
// This imports XLS's one-block SHA-256 compression implementation with the
// standard fixed IV. The 512-bit block input is intentionally unrestricted.
// The property below claims it is injective. It is false by pigeonhole
// principle (512 input bits, 256 output bits), but a counterexample would be a
// collision for the fixed-IV SHA-256 compression function. That is expected to
// be far beyond a normal bit-vector SMT proof run.
//
// This is not a claim about a collision in the full variable-length SHA-256
// message hash: arbitrary blocks here need not be valid padded messages.
// Solver timeout or resource exhaustion is not evidence that SHA-256 is secure.
//
// CMake target (intentionally not part of formal_crc):
//   cmake --build build --target formal_sha256_collision_hard
// To bound an experiment on GNU/Linux:
//   timeout 60s cmake --build build --target formal_sha256_collision_hard

import sha256;

#[quickcheck]
fn prop_sha256_compression_is_injective(a: bits[512], b: bits[512]) -> bool {
    (a == b) || (sha256::sha256(a) != sha256::sha256(b))
}
