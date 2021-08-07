-- | Initialize a big number of `n` digits, representing the value `c`. `c` is at most one digit.
let big_small_constant (n: i64) (c: u64) =
    let arr = replicate n 0u64
    in arr with [0] = c

-- | Zero the high half digits of `a`.
let big_zero_h [n] (a: [n]u64) =
    map2
        (\i x -> if i >= n / 2 then 0 else x)
        (iota n)
        a

-- | Swap the higher and lower half digits of `a`
let big_swap_hl [n] (a: [n]u64) =
    rotate (n / 2) a

-- | Move the upper half of `a` into the lower half. The upper half is zero after.
let big_h_to_l [n] (a: [n]u64) =
    a |> big_swap_hl |> big_zero_h

-- | Shift left by `k` bits. Zeroes are shifted into the low bits
let big_shl [n] (a: [n]u64) (k: u64) =
    map2
        (\i x -> if i == 0
            then (x << k)
            else (x << k) | (a[i - 1] >> (64 - k)))
        (iota n)
        a
