const std = @import("std");
const Int = std.math.big.int.Managed;

fn powbig(b: u64, p: Int) u64 {
    var res: u64 = 1;
    var x = b;

    for (p.limbs[0..p.len()]) |limb| {
        var lp = limb;
        while (lp != 0) {
            if (lp & 1 != 0) res *%= x;
            x *%= x;
            lp >>= 1;
        }
    }

    return res;
}

fn powbigbig(allocator: *std.mem.Allocator, b: Int, p: Int, m: Int) !Int {
    var res = try Int.initSet(allocator, 1);
    var x = try Int.init(allocator);
    try x.copy(b.toConst());

    var tmp0 = try Int.init(allocator);
    var tmp1 = try Int.init(allocator);

    std.debug.print("p limbs: {}\n", .{p.len()});

    for (p.limbs[0..p.len()]) |limb| {
        var lp = limb;
        var j: usize = 64;
        while (lp != 0) {
            if (lp & 1 != 0) {
                try tmp0.mul(res.toConst(), x.toConst());
                try tmp1.divFloor(&res, tmp0.toConst(), m.toConst());
            }

            try tmp0.sqr(x.toConst());
            try tmp1.divTrunc(&x, tmp0.toConst(), m.toConst());

            j -= 1;
            std.debug.print("{}\n", .{j});

            lp >>= 1;
        }
    }

    return res;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const k = 46157;
    const n = 698207;
    const a = 9;

    var _2n = try Int.initSet(allocator, 1);
    try _2n.shiftLeft(_2n, n);

    var _2nm1 = try Int.initSet(allocator, 1);
    try _2nm1.shiftLeft(_2nm1, n - 1);

    var big_k = try Int.initSet(allocator, k);

    var p = try Int.init(allocator);
    try p.mul(big_k.toConst(), _2n.toConst());
    try p.addScalar(p.toConst(), 1);

    std.debug.print("p = {}\n", .{p});

    var k2nm1 = try Int.init(allocator);
    try k2nm1.mul(big_k.toConst(), _2nm1.toConst());

    std.debug.print("(p-1)/2 = {}\n", .{k2nm1});

    const big_a = try Int.initSet(allocator, a);

    var result = try powbigbig(allocator, big_a, k2nm1, p);

    try result.addScalar(result.toConst(), 1);

    std.debug.print("a^((p-1)/2) + 1 = {}\n", .{result});

    var q = try Int.init(allocator);
    var r = try Int.init(allocator);

    try q.divFloor(&r, result.toConst(), p.toConst());

    std.debug.print("{}\n", .{r.eqZero()});
}
