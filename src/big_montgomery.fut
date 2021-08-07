local import "big_sum"
local import "big_mul"
local import "big_util"
local import "util"

-- | Compute r^-1 (mod a), where r = 2^(n/2)
-- Upper digits of `a` needs to be zeroed
let big_montgomery_invert [n] (a: [n]u64): [n]u64 =
    let bits = n / 2 * 64
    let k = ceil_log_2 bits
    let big_one = big_small_constant n 1
    let big_two = big_small_constant n 2
    in iterate
        (i32.i64 k)
        (\inv ->
            let x = big_mul_l a inv -- Result is already modulo m
            let y = big_sub big_two x |> big_zero_h -- Result of sub needs an explicit modulo
            in big_mul_l inv y) -- Result is already modulo m
        big_one

-- | Compute xr^-1 (mod m), where r = 2^(n/2)
-- Upper digits of m, inv need to be zeroed
let big_montgomery_reduce [n] (m: [n]u64) (inv: [n]u64) (x: [n]u64) =
    let q = x |> big_zero_h |> big_mul inv |> big_zero_h
    let (underflow, a) = big_sbc (big_h_to_l x) (q `big_mul_h` m)
    in if underflow
        then big_add a m
        else a

-- | Compute abr^-1 (mod m) for a, b in montgomery space and where r = 2^(n/2)
-- Upper digits of m, inv, a, b need to be zeroed
let big_montgomery_multiply [n] (m: [n]u64) (inv: [n]u64) (a: [n]u64) (b: [n]u64): [n]u64 =
    big_mul a b |> big_montgomery_reduce m inv

-- | Compute r^2 (mod m), where r = 2^(n/2)
-- Seed is -m % m (mod r)
let big_montgomery_compute_r2 [n] (m: [n]u64) (inv: [n]u64) (seed: [n]u64) =
    -- Compute r * 2^4 (mod n) (2^4 in montgomery space)
    let r2 =
        iterate
            4
            (\r2 ->
                let r2 = big_shl r2 1
                let (underflow, result) = big_sbc r2 m
                in if underflow
                    then r2
                    else result)
                --  let r2 = r2 << 1
                --  in if r2 >= n then r2 - n else r2)
            seed
    -- Compute r^2 (mod n) (r in montgomery space) by squaring r2 log2(bits/4) times (in montgomery space)
    let bits = n / 2 * 64
    let k = ceil_log_2 (bits / 4)
    in iterate
        (i32.i64 k)
        (\r2 -> big_montgomery_multiply m inv r2 r2)
        r2

-- | Convert a number to montgomery space
let big_montgomery_convert_to [n] (m: [n]u64) (inv: [n]u64) (r2: [n]u64) (x: [n]u64): [n]u64 =
    big_montgomery_multiply m inv r2 x

-- | Convert a number from montgomery space, where r = 2^(n/2)
let big_montgomery_convert_from [n] (m: [n]u64) (inv: [n]u64) (x: [n]u64): [n]u64 =
    big_montgomery_reduce m inv x

let main =
    --  let a = big_small_constant n 4261675009
    let a = [16762916038367820851u64, 22370, 0, 0] -- 412670427844921037470771
    let a' = big_montgomery_invert a
    in a'
    --  in big_shl a 1
