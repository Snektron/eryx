local import "montgomery"

-- | Return whether the argument is a power of 2
let is_power_of_2 (x: i64): bool = x & (x - 1) == 0

-- | Compute ceil(log2(x))
-- let ceil_log_2 (x: i64): i64 = i64.i32 i64.num_bits - (x - 1 |> u64.i64 |> u64.clz |> i64.i32)
-- Iterative version to work around futhark undefined behaviour
let ceil_log_2 (n: i64): i64 =
    let r = 0
    let (r, _) = loop (r, n) while 1 < n do
        let n = n / 2
        let r = r + 1
        in (r, n)
    in r

-- | Compute (base ^ exponent) % mod
let powmod (base: u64) (exponent: u64) (mod: u64) =
    let inv = montgomery_invert mod
    let r2 = montgomery_compute_r2 mod inv
    let base = montgomery_convert_to mod inv r2 base
    let one = montgomery_convert_to mod inv r2 1
    let result = montgomery_pow mod inv one base exponent
    in montgomery_convert_from mod inv result

-- | Compute x^-1 (mod m)
let reciprocal_mod (x: u64) (m: u64): u64 =
    let (t, r, _, _) =
        loop (t, r, newt, newr) = (0, m, 1, x) while newr != 0 do
            let quotient = r / newr
            let (t, newt) = (newt, t - quotient * newt)
            let (r, newr) = (newr, r - quotient * newr)
            in (t, r, newt, newr)
    in assert (r == 1) (if t > m then t + m else t)
