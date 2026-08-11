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

    let next_crc = crc16_byte(crc, input.data);
    let tok = send_if(tok, output, input.last, next_crc);

    if input.last {
      u16:0
    } else {
      next_crc
    }
  }
}
