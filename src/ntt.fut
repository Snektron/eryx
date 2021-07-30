local import "util"
local import "montgomery"

local let ntt_iteration [n] (prime: u64) (inv_prime: u64) (w: []u64) (a: [n]u64) (ns: i64) (j: i64) =
    let k = (j % ns) * n / (ns * 2)
    let v0 = a[j]
    let v1 = montgomery_multiply prime inv_prime w[k] a[j + n / 2]
    let (v0, v1) = (if v0 + v1 >= prime then v0 + v1 - prime else v0 + v1,
        if v0 - v1 > prime then v0 - v1 + prime else v0 - v1)
    let i0 = (j / ns) * ns * 2 + j % ns
    let i1 = i0 + ns
    in (i0, v0, i1, v1)

-- | Compute the Number Theoretical Transform on the input.
-- `w` and `input` are expected to be in montgomery space with regards to `prime`.
-- `inv_prime` is the inverse computed by `montgomery_invert prime`
let ntt [n] (prime: u64) (inv_prime: u64) (w: []u64) (input: [n]u64): [n]u64 =
    let bits = assert (is_power_of_2 n) (ceil_log_2 n)
    let NS = map (2**) (iota bits)
    let js = iota (n / 2)
    let input = copy input
    let output = copy input
    let (res, _) =
        loop (input, output) = (input, output) for ns in NS do
            let (i0s, v0s, i1s, v1s) =
                js
                |> map (ntt_iteration prime inv_prime w input ns)
                |> unzip4
            let output' =
                scatter
                    output
                    (i0s ++ i1s :> [n]i64)
                    (v0s ++ v1s :> [n]u64)
            in (output', input)
    in res :> [n]u64

-- | Compute the Inverse Number Theoretical Transform on the input.
-- `inv_w` and `input` are expected to be in montgomery space with regards to `prime`.
-- `inv_prime` is the inverse computed by `montgomery_invert prime`
let intt [n] (prime: u64) (inv_prime: u64) (inv_n: u64) (inv_w: []u64) (input: [n]u64): [n]u64 =
    ntt prime inv_prime inv_w input
    |> map (montgomery_multiply prime inv_prime inv_n)

--  4261675009
--  8384598389812410000