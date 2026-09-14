// Process all 128 bits, most significant bit first.
// The loop is unrolled into one combinational circuit without registers.
// Pass zero as crc for a new packet, or the previous CRC to continue it.
pub fn crc16_block(crc: u16, data: uN[128]) -> u16 {
  for (i, accum): (u32, u16) in u32:0..u32:128 {
    let bit = (data >> (u32:127 - i)) as u1;
    let feedback = accum[15:16] ^ bit;
    let shifted = accum << u32:1;
    if feedback { shifted ^ u16:0x1021 } else { shifted }
  }(crc)
}
