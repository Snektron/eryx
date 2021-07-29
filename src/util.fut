-- | Return whether the argument is a power of 2
let is_power_of_2 (x: i64): bool = x & (x - 1) == 0

-- | Compute ceil(log2(x))
-- let ceil_log_2 (x: i64): i64 = i64.i32 i64.num_bits - (x - 1 |> u64.i64 |> u64.clz |> i64.i32)
-- Iterative version to work around futhark undefined behaviour
let ceil_log_2 (n: i64): i64 =
    let r = 0
    let (r, _) = loop (r,n) while 1 < n do
        let n = n / 2
        let r = r + 1
        in (r,n)
    in r

-- | Compute (base ^ exponent) % mod
let powmod (base: i64) (ex: i64) (mod: i64) =
    let (result, _) =
        loop (result, x) = (1, base) for i < 64 do
            let bit = (ex >> i) & 1
            let result' = if bit == 1 then (result * x) % mod else result
            in (result', (x * x) % mod)
    in result

-- | Compute x^-1 (mod m)
let reciprocal_mod (x: i64) (m: i64): i64 =
    let (t, r, _, _) =
        loop (t, r, newt, newr) = (0, m, 1, x) while newr != 0 do
            let quotient = r / newr
            let (t, newt) = (newt, t - quotient * newt)
            let (r, newr) = (newr, r - quotient * newr)
            in (t, r, newt, newr)
    in assert (r == 1) (if t < 0 then t + m else t)
