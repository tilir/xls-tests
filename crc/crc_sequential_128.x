// One 128-bit block per transaction, MSB first. The caller supplies the
// initial CRC (zero for a new packet, previous result for block chaining).
// Reuse a small CRC step across cycles instead of unrolling the whole block.
// 16 bits/step: eight processing steps, selected by the synthesis sweep.
const STEP_BITS = u32:16;

struct Input {
  crc: u16,
  data: uN[128],
}

struct State {
  data: uN[128],
  crc: u16,
  remaining: u7,
}

proc Crc16Sequential128 {
  input: chan<Input> in;
  output: chan<u16> out;

  config(input: chan<Input> in, output: chan<u16> out) {
    const_assert!(STEP_BITS > u32:0 && STEP_BITS < u32:128);
    const_assert!(u32:128 % STEP_BITS == u32:0);
    (input, output)
  }

  init { State { data: uN[128]:0, crc: u16:0, remaining: u7:0 } }

  next(state: State) {
    let idle = state.remaining == u7:0;
    let (tok, block) = recv_if(join(), input, idle,
                              Input { crc: u16:0, data: uN[128]:0 });
    let data = if idle { block.data } else { state.data };
    let crc = if idle { block.crc } else { state.crc };
    let crc = for (i, accum): (u32, u16) in u32:0..STEP_BITS {
      let bit = (data >> (u32:127 - i)) as u1;
      let feedback = accum[15:16] ^ bit;
      let shifted = accum << u32:1;
      if feedback { shifted ^ u16:0x1021 } else { shifted }
    }(crc);
    // A stalled output blocks this final step and preserves its result.
    let tok = send_if(tok, output, state.remaining == u7:1, crc);
    State {
      data: data << STEP_BITS,
      crc,
      remaining: if idle { (u32:128 / STEP_BITS - u32:1) as u7 }
                 else { state.remaining - u7:1 },
    }
  }
}
