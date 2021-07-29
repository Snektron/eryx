-- https://cp-algorithms.com/algebra/montgomery_multiplication.html

-- | Number of bits in a montgomery word. We use 64-bit words here.
local let bits = 6i32 -- log2(64)

-- | Compute r^-1 (mod n)
let montgomery_invert (n: u64): u64 =
    iterate
        bits
        (\inv -> inv * (2 - n * inv))
        1u64

-- | Compute xr^-1 (mod n) for x = ((hi << bits) | lo)
let montgomery_reduce (n: u64) (inv: u64) (hi: u64) (lo: u64): u64 =
    let q = lo * inv
    let a = hi - u64.mul_hi q n
    in if a > n then a + n else a

-- | Compute abr^-1 (mod n) for a, b in montgomery space
let montgomery_multiply (n: u64) (inv: u64) (a: u64) (b: u64): u64 =
    let hi = u64.mul_hi a b
    let lo = a * b
    in montgomery_reduce n inv hi lo

-- | Compute r^2 (mod n)
let montgomery_compute_r2 (n: u64) (inv: u64): u64 =
    -- Compute r * 2^4 (mod n) (2^4 in montgomery space)
    let r2 =
        iterate
            4
            (\r2 ->
                let r2 = r2 << 1
                in if r2 >= n then r2 - n else r2)
            ((-n) % n)
    -- Compute r^2 (mod n) (r in montgomery space) by squaring r2 four times (in montgomery space)
    in iterate
        4
        (\r2 -> montgomery_multiply n inv r2 r2)
        r2

-- | Convert a number to montgomery space
let montgomery_convert_to (n: u64) (inv: u64) (r2: u64) (x: u64): u64 =
    montgomery_multiply n inv r2 x

-- | Convert a number from montgomery space
let montgomery_convert_from (n: u64) (inv: u64) (x: u64): u64 =
    montgomery_reduce n inv 0 x

let montgomery_pow (n: u64) (inv: u64) (one: u64) (base: u64) (exponent: u64): u64 =
    let (result, _) =
        loop (result, x) = (one, base) for i < 64 do
            let bit = (exponent >> (u64.i64 i)) & 1
            let result = if bit == 1 then montgomery_multiply n inv result x else result
            let x = montgomery_multiply n inv x x
            in (result, x)
    in result

entry main =
    let a = 5315
    let b = 249366121
    let n = 4261675009
    let inv = montgomery_invert n
    let r2 = montgomery_compute_r2 n inv
    let a = montgomery_convert_to n inv r2 a
    let b = montgomery_convert_to n inv r2 b
    let c = montgomery_multiply n inv a b
    in montgomery_convert_from n inv c
