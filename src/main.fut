let add [n] (a: [n]u64) (b: [n]u64) =
    let acc (a: u64) (b: u64): (bool, u64) =
        let r = a + b
        in (r < a, r)
    let f (yc, _) (xc, x) =
        let (overflow, z) = acc x (u64.bool yc)
        in (overflow || xc, z)
    let r = map2 acc a b |> scan f (false, 0)
    let (overflow, _) = last r
    let c = map (.1) r
    in (overflow, c)

let sub [n] (a: [n]u64) (b: [n]u64) =
    let acc (a: u64) (b: u64): (bool, u64) =
        let r = a - b
        in (r > a, r)
    let f (yc, _) (xc, x) =
        let (underflow, z) = acc x (u64.bool yc)
        in (underflow || xc, z)
    let r = map2 acc a b |> scan f (false, 0)
    let (underflow, _) = last r
    let c = map (.1) r
    in (underflow, c)

entry main [n] (_: [n]u64) =
    let (underflow, result) = sub (reverse [1, 0, 0, 0, 0]) (reverse [1, 0, 0, 0, 1])
    in reverse (result ++ [u64.bool underflow])
