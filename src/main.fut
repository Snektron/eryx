import "sum"
import "mul"

entry mul (a: []u64) (b: []u64) = mul a b

--  entry main [n] (_: [n]u64) =
--      let (underflow, result) = add (reverse [1, 0, 0, 0, 0]) (reverse [1, 0, 0, 0, 1])
--      in reverse (result ++ [u64.bool underflow])

--  entry main [n] (a: [n]u64) (b: [n]u64) = mul a b