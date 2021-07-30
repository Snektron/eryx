local import "ntt"
local import "util"
local import "montgomery"
local import "sum"

-- | Arrays generated for base 256
local let base = 256u64

-- | All arrays are valid for powers < 20
local let max_n_log2 = 20i64

-- | primes[i] returns the working modulus for n = 2**i
local let primes: []u64 = [
    65027, 130051, 260137, 520241, 1040449,
    2080801, 4161793, 8323201, 16646401, 33292801,
    66598913, 133183489, 266407937, 532709377, 1065484289,
    2131918849, 4261675009, 8526364673, 17052205057, 34091827201,
    68206723073, 136384086017, 272772366337, 545511178241, 1091139796993,
    2181876940801
]

-- | primitive_roots[i] gives the nth primitive root for n = 2**i and N = primes[i]
local let primitive_roots: []u64 = [
    1, 130050, 13475, 118272, 34351, 40132,
    217153, 17627, 41766, 652807, 71476,
    120308, 122521, 208575, 175977, 110455,
    5315, 32915, 214273, 14332, 270415,
    284784, 75574, 25920, 455367, 204843
]

local let expand_limbs [n] (a: [n]u64): []u64 =
    a
    |> map (\i -> [i, i >> 8, i >> 16, i >> 24, i >> 32, i >> 40, i >> 48, i >> 56])
    |> flatten
    |> map (& 0xFF)

local let contract_limbs [n] (a: [n]u64): []u64 =
    a
    |> unflatten (n / 8) 8
    |> map (\b -> b[0]
        | (b[1] << 8u64)
        | (b[2] << 16u64)
        | (b[3] << 24u64)
        | (b[4] << 32u64)
        | (b[5] << 40u64)
        | (b[6] << 48u64)
        | (b[7] << 56u64))

local let carry_and_contract_256 [n] (as: [n]u64) =
    -- Split the limbs
    let m = n / 8
    let f (i: i64) =
        let limbs =
            as
            -- Fetch the right elements
            |> map (>> (u64.i64 i * 8))
            |> map (& 0xFF)
            -- Rotate so they match up with the place to put them
            |> rotate (-i)
            |> map2 (\j x -> if j < i then 0 else x) (iota n)
            -- Contract them to u64s
            |> contract_limbs
        in limbs :> [m]u64
    let bs = tabulate 8 f
    -- Add all the integers together to get the final result
    in foldr add bs[0] bs[1:]

-- | Compute ws[] and invws[] for arrays of length n
-- The outputs are in montgomery space wrt `prime`.
local let precompute_roots (n: i64) (prime: u64) (inv_prime: u64) (r2: u64) (one: u64) =
    let log_n = assert (is_power_of_2 n) (ceil_log_2 n)
    -- Initialize w
    let w = primitive_roots[log_n]
    let inv_w = reciprocal_mod w prime
    let w = montgomery_convert_to prime inv_prime r2 w
    let inv_w = montgomery_convert_to prime inv_prime r2 inv_w
    -- Compute the final arrays using montgomery
    let ws =
        iota (n / 2)
        |> map u64.i64
        |> map (montgomery_pow prime inv_prime one w)
    let inv_ws =
        iota (n / 2)
        |> map u64.i64
        |> map (montgomery_pow prime inv_prime one inv_w)
    in (ws, inv_ws)

local let mul_base_256 [n] (a: [n]u64) (b: [n]u64) =
    let log_n = assert (is_power_of_2 n) (ceil_log_2 n)
    let prime = primes[log_n]
    let inv_n = reciprocal_mod (u64.i64 n) prime
    -- Initialize montgomery values
    let inv_prime = montgomery_invert prime
    let r2 = montgomery_compute_r2 prime inv_prime
    let one = montgomery_convert_to prime inv_prime r2 1
    let inv_n = montgomery_convert_to prime inv_prime r2 inv_n
    -- Pre-compute ntt powers
    let (ws, inv_ws) = precompute_roots n prime inv_prime r2 one
    -- Convert inputs into montgomery space
    let a = map (montgomery_convert_to prime inv_prime r2) a
    let b = map (montgomery_convert_to prime inv_prime r2) b
    -- Perform the actual multiplication
    let a' = ntt prime inv_prime ws a
    let b' = ntt prime inv_prime ws b
    let h' = map2 (montgomery_multiply prime inv_prime) a' b'
    let h = intt prime inv_prime inv_n inv_ws h'
    -- Convert the result back to normal space
    let h = map (montgomery_convert_from prime inv_prime) h
    -- Finally, fix the carries
    in carry_and_contract_256 h

let mul [n] (a: [n]u64) (b: [n]u64) =
    let a = expand_limbs a
    let b = expand_limbs b
    let m = length a
    in mul_base_256 (a :> [m]u64) (b :> [m]u64)
