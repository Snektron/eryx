local type carry = #carry | #maybe | #no

let add [n] (a: [n]u64) (b: [n]u64) =
    let p = map2 (+) a b
    in
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
        |> rotate (-1)
        |> map2 (\i x -> i != 0 && x) (iota n)
        |> map u64.bool
        |> map2 (+) p
