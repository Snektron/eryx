-- | Return whether the argument is a power of 2
let is_power_of_2 (x: i64): bool = x & (x - 1) == 0

-- | Compute ceil(log2(x))
let ceil_log_2 (x: i64): i64 = i64.i32 i64.num_bits - (x - 1 |> i64.clz |> i64.i32)

-- | Compute (base * exponent) % mod
let powmod (base: i64) (ex: i64) (mod: i64) =
    let (result, _) =
        loop (result, x) = (1, base) for i < 64 do
            let bit = (ex >> i) & 1
            let result' = if bit == 1 then result * x % mod else result
            in (result', x * x % mod)
    in result