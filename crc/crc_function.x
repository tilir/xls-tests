// Pure byte update, with eight bit steps unrolled by the compiler.
// The caller owns the accumulator; initialize it to zero for a new packet.
const CRC16_POLY = u16:0x1021;

fn crc16_step(crc: u16, bit: u1) -> u16 {
  let feedback = crc[15:16] ^ bit;
  let shifted = crc << u32:1;
  if feedback { shifted ^ CRC16_POLY } else { shifted }
}

pub fn crc16_byte(crc: u16, data: u8) -> u16 {
  let data_bits = data as u1[8];
  for (i, accum): (u32, u16) in u32:0..u32:8 {
    crc16_step(accum, data_bits[i])
  }(crc)
}
