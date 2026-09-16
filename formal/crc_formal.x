// A self-contained DSLX: concrete tests, QuickCheck, and SMT proofs.

const CRC16_POLY = u16:0x1021;
const CRC16_POLYNOMIAL = uN[144]:0x11021;

// Implementation under test
pub fn crc16_block(crc: u16, data: uN[128]) -> u16 {
    for (i, accum): (u32, u16) in u32:0..u32:128 {
        let bit = (data >> (u32:127 - i)) as u1;
        let feedback = accum[15:16] ^ bit;
        let shifted = accum << u32:1;
        if feedback { shifted ^ CRC16_POLY } else { shifted }
    }(crc)
}

// Independent specification: divide crc*x^128 + data*x^16 by
// x^16 + x^12 + x^5 + 1 (0x11021). `data` is MSB-first, so its low-order
// coefficient is shifted by x^16 before division. This is intentionally a
// polynomial long-division formulation, not another LFSR recurrence.
fn crc16_polynomial_reference(crc: u16, data: uN[128]) -> u16 {
    let dividend = ((crc as uN[144]) << u32:128) ^ ((data as uN[144]) << u32:16);
    let remainder = for (i, remainder): (u32, uN[144]) in u32:0..u32:128 {
        let degree = u32:143 - i;
        let aligned_divisor = CRC16_POLYNOMIAL << (degree - u32:16);
        if remainder[degree+:u1] { remainder ^ aligned_divisor } else { remainder }
    }(dividend);
    remainder as u16
}

// Fixed-width helper used by the streaming composition property.
fn crc16_block64(crc: u16, data: uN[64]) -> u16 {
    for (i, accum): (u32, u16) in u32:0..u32:64 {
        let bit = (data >> (u32:63 - i)) as u1;
        let feedback = accum[15:16] ^ bit;
        let shifted = accum << u32:1;
        if feedback { shifted ^ CRC16_POLY } else { shifted }
    }(crc)
}

#[test]
fn test_crc16_123456789() {
    // CRC-16/XMODEM of ASCII "123456789" with zero initial state is 0x31c3.
    // The leading zero bits in this uN[128] value leave a zero initial state unchanged.
    assert_eq(crc16_block(u16:0, uN[128]:0x313233343536373839), u16:0x31c3)
}

fn reverse_u8(x: u8) -> u8 {
    for (i, accum): (u32, u8) in u32:0..u32:8 {
        (accum << u32:1) | (x[i+:u1] as u8)
    }(u8:0)
}

// Random samples when interpreter_main runs this property.
#[quickcheck(test_count=100)]
fn prop_reverse_u8_involution(x: u8) -> bool { reverse_u8(reverse_u8(x)) == x }

// Exactly 16 concrete calls when interpreter_main runs this property.
#[quickcheck(exhaustive)]
fn prop_xor_u4_exhaustive(x: u4) -> bool { (x ^ x) == u4:0 }

// Formal proof: the recurrence matches polynomial division for every one of
// the 2^144 possible initial-state and input-block pairs.
#[quickcheck]
fn prop_crc16_matches_polynomial(crc: u16, data: uN[128]) -> bool {
    crc16_block(crc, data) == crc16_polynomial_reference(crc, data)
}

// Formal proof of linearity. It is structurally useful, but it is not a full
// specification: a design using the wrong *linear* polynomial still passes.
#[quickcheck]
fn prop_crc16_linear(crc_a: u16, crc_b: u16, data_a: uN[128], data_b: uN[128]) -> bool {
    crc16_block(crc_a ^ crc_b, data_a ^ data_b) ==
    (crc16_block(crc_a, data_a) ^ crc16_block(crc_b, data_b))
}

// Formal proof of the 64+64 streaming composition law for A || B.
#[quickcheck]
fn prop_crc16_composes_64_64(crc: u16, data: uN[128]) -> bool {
    let a = (data >> u32:64) as uN[64];
    let b = data as uN[64];
    crc16_block(crc, data) == crc16_block64(crc16_block64(crc, a), b)
}

// Deliberately false and excluded from the passing commands above. Prove just
// this property to see the current XLS tool print `counterexample
// prove_quickcheck_main --test_filter=prop_crc16_false_ignores_initial_state formal/crc_formal.x
#[quickcheck]
fn prop_crc16_false_ignores_initial_state(crc: u16, data: uN[128]) -> bool {
    crc16_block(crc, data) == crc16_block(u16:0, data)
}
