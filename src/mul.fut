local import "ntt"
local import "util"

--  let prime = 673i64
--  let w: []i64 = [1, 64, 58, 347]
--  let invw: []i64 = [1, 326, 615, 609]
--  let invn = 589i64

-- | Arrays generated for base 10
let base = 10i64

-- | All arrays are valid for powers < 20
let max_n_log2 = 20i64

-- | primes[i] returns the working modulus for n = 2**i
-- Note: base 10
let primes: []i64 = [
    83, 163, 337, 673, 1297,
    2593, 5441, 10369, 22273, 45569,
    83969, 176129, 331777, 737281, 1376257,
    2654209, 5308417, 11272193, 21495809, 68681729
]

-- | primitive_roots[i] gives the nth primitive root for n = 2**i and N = primes[i]
-- Note: base 10
let primitive_roots: []i64 = [
    1, 162, 148, 64, 157,
    5, 77, 171, 281, 365,
    329, 153, 386, 96, 73,
    89, 167, 85, 144, 378
]

-- | primitive_roots[i] gives the inverse nth primitive root for n = 2**i and N = primes[i]
-- Note: base 10
let inverse_primitive_roots: []i64 = [
    1, 162, 189, 326, 1107,
    1556, 212, 4851, 20767, 21973,
    10209, 115117, 116036, 729601, 1263140,
    2445451, 445017, 3713193, 4627570, 64502682
]

-- | inverse_lengths[i] gives n**(-1) % N for n = 2**i and N = primes[i]
-- Note: base 10
let inverse_lengths: []i64 = [
    1, 82, 253, 589, 1216,
    2512, 5356, 10288, 22186, 45480,
    83887, 176043, 331696, 737191, 1376173,
    2654128, 5308336, 11272107, 21495727, 68681598
]

local let carry10s [n] (as: [n]i64) =
    let acc (a: i64) (b: i64) =
        let r = a + b
        in (r / 10, r % 10)
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

let mul [n] (a: [n]i64) (b: [n]i64) =
    let log_n = assert (is_power_of_2 n) (ceil_log_2 n)
    let prime = primes[log_n]
    let invn = inverse_lengths[log_n]
    let (ws, invws) = precompute_roots n
    let a' = ntt prime ws a
    let b' = ntt prime ws b
    let h' = map2 (*) a' b'
    let h = intt prime invws invn h'
    in carry10s h

entry main = mul (reverse [0, 0, 0, 0, 0, 1, 2, 3]) (reverse [0, 0, 0, 0, 0, 4, 5, 6]) |> reverse
