const CRC16_POLY = u16:0x1021;

struct Input {
  data: u8,
  last: bool,
}

fn crc16_step(crc: u16, bit: u1) -> u16 {
  let feedback = crc[15:16] ^ bit;
  let shifted = crc << u32:1;

  if feedback {
    shifted ^ CRC16_POLY
  } else {
    shifted
  }
}

fn crc16_byte(crc: u16, data: u8) -> u16 {
  let data_bits = data as u1[8];

  for (i, accum): (u32, u16) in u32:0..u32:8 {
    crc16_step(accum, data_bits[i])
  }(crc)
}

// Combinational transition of Crc16. The caller stores next_crc and uses
// output_valid to decide whether output_crc completes a packet.
pub fn crc16_tick(crc: u16, byte_input: Input) -> (u16, u16, bool) {
  let output_crc = crc16_byte(crc, byte_input.data);
  let next_crc = if byte_input.last { u16:0 } else { output_crc };
  (next_crc, output_crc, byte_input.last)
}

proc Crc16 {
  input: chan<Input> in;
  output: chan<u16> out;

  config(input: chan<Input> in, output: chan<u16> out) {
    (input, output)
  }

  init { u16:0 }

  next(crc: u16) {
    let tok = join();
    let (tok, input) = recv(tok, input);

    let (next_crc, output_crc, output_valid) = crc16_tick(crc, input);
    let tok = send_if(tok, output, output_valid, output_crc);
    next_crc
  }
}
