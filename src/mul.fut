local import "ntt"
local import "util"

-- | Arrays generated for base 10
let base = 256i64

-- | All arrays are valid for powers < 20
let max_n_log2 = 20i64

-- | primes[i] returns the working modulus for n = 2**i
let primes: []i64 = [
    65027, 130051, 260137, 520241, 1040449,
    2080801, 4161793, 8323201, 16646401, 33292801,
    66598913, 133183489, 266407937, 532709377, 1065484289,
    2131918849, 4261675009, 8526364673, 17052205057, 34091827201
]

-- | primitive_roots[i] gives the nth primitive root for n = 2**i and N = primes[i]
let primitive_roots: []i64 = [
    1, 130050, 13475, 118272, 34351,
    40132, 217153, 17627, 41766, 652807,
    71476, 120308, 122521, 208575, 175977,
    110455, 5315, 32915, 214273, 14332
]

-- | primitive_roots[i] gives the inverse nth primitive root for n = 2**i and N = primes[i]
let inverse_primitive_roots: []i64 = [
    1, 130050, 246662, 309874, 865380,
    970560, 1613063, 7771217, 5329989, 32264091,
    38786627, 91120010, 202824544, 443029289, 36751903,
    1431399518, 249366120, 2573063354, 9875210938, 32081808084
]

-- | inverse_lengths[i] gives n**(-1) % N for n = 2**i and N = primes[i]
let inverse_lengths: []i64 = [
    1, 65026, 195103, 455211, 975421,
    2015776, 4096765, 8258176, 16581376, 33227776,
    66533875, 133118458, 266342896, 532644349, 1065419257,
    2131853788, 4261609981, 8526299622, 17052140008, 34091762176
]

local let carry [n] (as: [n]i64) =
    let acc (a: i64) (b: i64) =
        let r = a + b
        in (r / base, r % base)
    let f (yc, _) (xc, x) =
        let (overflow, z) = acc x yc
        in (overflow + xc, z)
    in
        as
        |> map (acc 0)
        |> scan f (0, 0)
        |> map (.1)

-- | Compute ws[] and invws[] for arrays of length n
local let precompute_roots (n: i64) =
    let log_n = assert (is_power_of_2 n) (ceil_log_2 n)
    let prime = primes[log_n]
    let w = primitive_roots[log_n]
    let invw = inverse_primitive_roots[log_n]
    in
        iota (n / 2)
        |> map (\ex -> (powmod w ex prime, powmod invw ex prime))
        |> unzip

local let big = 1i64 << 32

local let mul_base_256 [n] (a: [n]i64) (b: [n]i64) =
    let log_n = assert (is_power_of_2 n) (ceil_log_2 n)
    let prime = primes[log_n]
    let invn = inverse_lengths[log_n]
    let (ws, invws) = precompute_roots n
    let a' = ntt prime ws a
    --  let b' = ntt prime ws b
    --  let h' = map2 (*) a' b' |> map (% prime)
    --  let h' = map (\x -> if x > big then h'[-x] else x) h'
    --  let h = intt prime invws invn h'
    in ws

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

let mul [n] (a: [n]u64) (b: [n]u64) =
    let _ = assert (is_power_of_2 n) 0
    let a = a |> map i64.u64
    let b = b |> map i64.u64
    let m = length a
    let h = mul_base_256 (a :> [m]i64) (b :> [m]i64)
    in h |> map u64.i64
