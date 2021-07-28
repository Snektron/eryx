local import "util"

--  let max_n = 8i64

--  let prime = 673i64

--  -- Index i holds the primitive root for n=2^i
--  let w: []i64 = [1, 64, 58, 347]
--  let invw: []i64 = [1, 326, 615, 609]
--  let invn = 589i64

local let ntt_iteration [n] (prime: i64) (w: []i64) (a: [n]i64) (ns: i64) (j: i64) =
    let k = (j % ns) * n / (ns * 2)
    let v0 = a[j]
    let v1 = w[k] * a[j + n / 2]
    let (v0, v1) = ((v0 + v1) % prime, (v0 - v1) % prime)
    let i0 = (j / ns) * ns * 2 + j % ns
    let i1 = i0 + ns
    in (i0, v0, i1, v1)

let ntt [n] (prime: i64) (w: []i64) (input: [n]i64): [n]i64=
    let bits = assert (is_power_of_2 n) (ceil_log_2 n)
    let NS = map (2**) (iota bits)
    let js = iota (n / 2)
    let input = copy input
    let output = copy input
    let (res, _) =
        loop (input, output) = (input, output) for ns in NS do
            let (i0s, v0s, i1s, v1s) =
                js
                |> map (ntt_iteration prime w input ns)
                |> unzip4
            let output' =
                scatter
                    output
                    (i0s ++ i1s :> [n]i64)
                    (v0s ++ v1s :> [n]i64)
            in (output', input)
    in res :> [n]i64

let intt [n] (prime: i64) (invw: []i64) (invn: i64) (input: [n]i64): [n]i64 =
    ntt prime invw input
    |> map (\x -> x * invn % prime)
