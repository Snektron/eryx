local type carry = #carry | #maybe | #no

let big_adc [n] (a: [n]u64) (b: [n]u64): (bool, [n]u64) =
    let p = map2 (+) a b
    let carry =
        map2
            (\p a ->
                if p == u64.highest then #maybe : carry
                else if p < a then #carry
                else #no)
            p
            a
        |> scan
            (\a b -> if b == #no || b == #carry then b else a)
            #maybe
        |> map (== #carry)
    let overflow = last carry
    let result =
        carry
        |> rotate (-1)
        |> map2 (\i x -> i != 0 && x) (iota n)
        |> map u64.bool
        |> map2 (+) p
    in (overflow, result)

let big_add [n] (a: [n]u64) (b: [n]u64): [n]u64 =
    (big_adc a b).1

let big_sbc [n] (a: [n]u64) (b: [n]u64): (bool, [n]u64) =
    let p = map2 (-) a b
    let carry =
        map2
            (\p a ->
                if p == 0 then #maybe : carry
                else if p > a then #carry
                else #no)
            p
            a
        |> scan
            (\a b -> if b == #no || b == #carry then b else a)
            #maybe
        |> map (== #carry)
    let underflow = last carry
    let result =
        carry
        |> rotate (-1)
        |> map2 (\i x -> i != 0 && x) (iota n)
        |> map u64.bool
        |> map2 (-) p
    in (underflow, result)

let big_sub [n] (a: [n]u64) (b: [n]u64): [n]u64 =
    (big_sbc a b).1
