import "sum"
import "mul"

entry main [n] (_: [n]u64) =
    let (underflow, result) = add (reverse [1, 0, 0, 0, 0]) (reverse [1, 0, 0, 0, 1])
    in reverse (result ++ [u64.bool underflow])
