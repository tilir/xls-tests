// Shift-and-add multiplication modulo 2^N.
//
// This is a standalone formal-scaling example. `prop_comm` is true for every
// input pair, but it compares two independently elaborated shift-and-add
// networks. Changing N makes the bit-vector formula substantially harder for
// the SMT solver. Keep N=10 as the runnable demonstration; use an external
// timeout before experimenting with larger values such as N=12.
const N = u32:10;

fn mul_sa(a: uN[N], b: uN[N]) -> uN[N] {
    for (i, acc) in u32:0..N {
        if ((b >> i) & uN[N]:1) == uN[N]:1 {
            acc + (a << i)
        } else {
            acc
        }
    }(uN[N]:0)
}

#[quickcheck]
fn prop_comm(a: uN[N], b: uN[N]) -> bool {
    mul_sa(a, b) == mul_sa(b, a)
}
