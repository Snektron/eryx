let acc (a: u64) (b: u64): (bool, u64) =
    let r = a + b
    in (r < a, r)

let add [n] (a: [n]u64) (b: [n]u64) =
    let r =
        map2 acc a b
        |> scan
            (\(yc, _) (xc, x) ->
                let (overflow, z) = acc x (u64.bool yc)
                in (overflow || xc, z))
            (false, 0)
    let (overflow, _) = last r
    let c = map (.1) r
    in (overflow, c)

entry main [n] (_: [n]u64) =
    add (reverse [0, 255, 255, 255, 255]) (reverse [0, 0, 0, 0, 1])
    |> (.1)
    |> reverse
