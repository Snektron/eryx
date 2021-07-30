local import "ntt"
local import "util"
local import "montgomery"
local import "sum"

-- | Arrays generated for base 256
local let base = 65536u64

-- | primes[i] returns the working modulus for n = 2**i
local let primes: []u64 = [
    4294836241, 8589672473, 17179344901, 34358689873, 68717379713,
    137434759361, 274869519361, 549739039361, 1099478075393, 2198956157953,
    4397912309761, 8795824601089, 17591649189889, 35183298502657, 70366596759553,
    140733194108929, 281466386907137, 562932773683201, 1125865550774273, 2251731097878529,
    4503462189465601, 9006924401999873, 18013848757862401, 36027698060984321, 72055395450880001,
    144110790264225793
]

-- | primitive_roots[i] gives the nth primitive root for n = 2**i and N = primes[i]
local let primitive_roots: []u64 = [
    1, 8589672472, 131070, 39281318, 6637672725,
    929365923, 4183439356, 10066301218, 24429555417, 2673733634,
    10558646608, 3609153121, 1210817349, 29070318506, 14695187759,
    3654209019, 284130316, 12527315439, 592301798, 540884737,
    29742652857, 10350322083, 2027949422, 1633251314, 1366598484,
    7668522963
]

local let expand_limbs [n] (a: [n]u64): []u64 =
    a
    |> map (\i -> [i, i >> 16, i >> 32, i >> 48])
    |> flatten
    |> map (& 0xFFFF)

local let contract_limbs [n] (a: [n]u64): []u64 =
    a
    |> unflatten (n / 4) 4
    |> map (\b -> b[0]
        | (b[1] << 16u64)
        | (b[2] << 32u64)
        | (b[3] << 48u64))

local let carry_and_contract_65536 [n] (as: [n]u64) =
    -- Split the limbs
    let m = n / 4
    let f (i: i64) =
        let limbs =
            as
            -- Fetch the right elements
            |> map (>> (u64.i64 i * 16))
            |> map (& 0xFFFF)
            -- Rotate so they match up with the place to put them
            |> rotate (-i)
            |> map2 (\j x -> if j < i then 0 else x) (iota n)
            -- Contract them to u64s
            |> contract_limbs
        in limbs :> [m]u64
    -- Add all the integers together to get the final result
    -- The below tabulate is really slow for some reason, so just write it out manually
    -- let bs = tabulate 4 f
    let bs = [f 0, f 1, f 2, f 3]
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

local let mul_base_65536 [n] (a: [n]u64) (b: [n]u64) =
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
    in carry_and_contract_65536 h

let mul [n] (a: [n]u64) (b: [n]u64) =
    let a = expand_limbs a
    let b = expand_limbs b
    let m = length a
    in mul_base_65536 (a :> [m]u64) (b :> [m]u64)
