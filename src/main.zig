const std = @import("std");
const build_options = @import("build_options");
const c = @cImport({
    @cInclude("malloc.h");
    @cInclude("futhark.h");
});

const big_int = std.math.big.int;

pub const log_level = .debug;

const Options = struct {
    help: bool,
    futhark_verbose: bool,
    futhark_debug: bool,

    // Options available for the multicore backend.
    threads: i32,

    // Options available for the OpenCL and CUDA backends.
    device_name: ?[:0]const u8,
    futhark_profile: bool,
};

fn parseOptions() !Options {
    var opts = Options{
        .help = false,
        .futhark_verbose = false,
        .futhark_debug = false,
        .threads = 0,
        .device_name = null,
        .futhark_profile = false,
    };

    const stderr = std.io.getStdErr().writer();

    var it = std.process.args();
    _ = it.nextPosix().?;
    while (it.nextPosix()) |arg| {
        switch (build_options.futhark_backend) {
            .c => {},
            .multicore => {
                if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--threads")) {
                    const threads_arg = it.nextPosix() orelse {
                        try stderr.print("Error: Missing argument <amount> for option {s}\n", .{arg});
                        return error.InvalidCmdline;
                    };

                    opts.threads = std.fmt.parseInt(i32, threads_arg, 0) catch {
                        return error.InvalidCmdline;
                    };
                    continue;
                }
            },
            .opencl, .cuda => {
                if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--device")) {
                    opts.device_name = it.nextPosix() orelse {
                        try stderr.print("Error: Missing argument <name> for option {s}\n", .{arg});
                        return error.InvalidCmdline;
                    };
                } else if (std.mem.eql(u8, arg, "--futhark-profile")) {
                    opts.futhark_profile = true;
                }
                continue;
            },
        }

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.help = true;
        } else if (std.mem.eql(u8, arg, "--futhark-verbose")) {
            opts.futhark_verbose = true;
        } else if (std.mem.eql(u8, arg, "--futhark-debug")) {
            opts.futhark_debug = true;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.InvalidCmdline;
        }
    }

    return opts;
}

fn printHelp() !void {
    const stderr = std.io.getStdErr().writer();
    const program_name = std.process.args().nextPosix().?;

    const backend_options = switch (build_options.futhark_backend) {
        .c => "",
        .multicore =>
        \\Available multicore backend options:
        \\-t --threads <amt>  Set the maximum number of threads that may be used
        \\                    (default: number of cores).
        ,
        .opencl, .cuda =>
        \\Available GPU backend options:
        \\-d --device <name>  Select the Futhark device.
        \\--futhark-profile   Enable Futhark profiling and report at exit.
        ,
    };

    try stderr.print(
        \\Usage: {s} [options...]
        \\Available options:
        \\-h --help           Show this message and exit.
        \\--futhark-verbose   Enable Futhark logging.
        \\--futhark-debug     Enable Futhark debug logging.
        \\
        ++ backend_options,
        .{program_name},
    );
}

fn futharkSync(ctx: *c.futhark_context) !void {
    if (c.futhark_context_sync(ctx) != 0) {
        return error.Sync;
    }
}

fn futharkReportError(ctx: *c.futhark_context) void {
    const maybe_msg = c.futhark_context_get_error(ctx);
    defer c.free(maybe_msg);

    const msg = if (maybe_msg) |msg|
        std.mem.spanZ(msg)
    else
        "(no diagnostic)";

    std.log.err("Futhark error: {s}\n", .{msg});
}

const GpuInt = struct {
    limbs: *c.futhark_u64_1d,

    fn init(ctx: *c.futhark_context, limbs: []const u64) !GpuInt {
        std.debug.assert(std.math.isPowerOfTwo(limbs.len));

        const gpu_limbs = c.futhark_new_u64_1d(ctx, limbs.ptr, @intCast(i64, limbs.len)) orelse return error.OutOfMemory;
        try futharkSync(ctx);
        return GpuInt{ .limbs = gpu_limbs };
    }

    fn initSmallConstant(ctx: *c.futhark_context, digits: u64, value: u64) !GpuInt {
        std.debug.assert(std.math.isPowerOfTwo(digits));
        return invokeKernel(c.futhark_entry_big_small_constant, ctx, .{ @intCast(i64, digits), value });
    }

    fn initRaw(ctx: *c.futhark_context, limbs: *c.futhark_u64_1d) GpuInt {
        const self = GpuInt{ .limbs = limbs };
        std.debug.assert(std.math.isPowerOfTwo(self.len(ctx)));
        return self;
    }

    fn initConst(ctx: *c.futhark_context, int: big_int.Const) !GpuInt {
        std.debug.assert(int.positive);
        return init(ctx, @ptrCast([*]const u64, int.limbs.ptr)[0..int.limbs.len]);
    }

    fn deinit(self: *GpuInt, ctx: *c.futhark_context) void {
        _ = c.futhark_free_u64_1d(ctx, self.limbs);
        self.* = undefined;
    }

    fn download(self: GpuInt, ctx: *c.futhark_context, int: *big_int.Managed) !void {
        const digits = self.len(ctx);
        try int.ensureCapacity(digits);
        int.setLen(digits);

        const err = c.futhark_values_u64_1d(ctx, self.limbs, int.limbs.ptr);
        if (err != 0) {
            return error.IntDownload;
        }
        try futharkSync(ctx);
        int.normalize(digits);
    }

    fn invokeKernel(comptime kernel: anytype, ctx: *c.futhark_context, inputs: anytype) !GpuInt {
        var dst: ?*c.futhark_u64_1d = null;
        errdefer if (dst) |ptr| {
            _ = c.futhark_free_u64_1d(ctx, ptr);
        };

        const err = @call(.{}, kernel, .{ ctx, &dst } ++ inputs);
        if (err != 0) {
            return error.Kernel;
        }

        return initRaw(ctx, dst.?);
    }

    fn clone(ctx: *c.futhark_context, a: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_clone, ctx, .{ a.limbs });
    }

    fn add(ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_add, ctx, .{ a.limbs, b.limbs });
    }

    fn sub(ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_sub, ctx, .{ a.limbs, b.limbs });
    }

    fn mul(ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_mul, ctx, .{ a.limbs, b.limbs });
    }

    fn montgomeryInvert(ctx: *c.futhark_context, m: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_montgomery_invert, ctx, .{m.limbs});
    }

    fn montgomeryComputeR2(ctx: *c.futhark_context, m: GpuInt, inv: GpuInt, seed: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_montgomery_compute_r2, ctx, .{ m.limbs, inv.limbs, seed.limbs });
    }

    fn montgomeryConvertTo(ctx: *c.futhark_context, m: GpuInt, inv: GpuInt, r2: GpuInt, x: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_montgomery_convert_to, ctx, .{ m.limbs, inv.limbs, r2.limbs, x.limbs });
    }

    fn montgomeryConvertFrom(ctx: *c.futhark_context, m: GpuInt, inv: GpuInt, x: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_montgomery_convert_from, ctx, .{ m.limbs, inv.limbs, x.limbs });
    }

    fn montgomeryMultiply(ctx: *c.futhark_context, m: GpuInt, inv: GpuInt, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeKernel(c.futhark_entry_big_montgomery_multiply, ctx, .{ m.limbs, inv.limbs, a.limbs, b.limbs });
    }

    fn montgomeryMultiplyTo(ctx: *c.futhark_context, dst: *GpuInt, m: GpuInt, inv: GpuInt, a: GpuInt, b: GpuInt) !void {
        var dst_limbs: ?*c.futhark_u64_1d = dst.limbs;
        const err = c.futhark_entry_big_montgomery_multiply(ctx, &dst_limbs, m.limbs, inv.limbs, a.limbs, b.limbs);
        if (err != 0) {
            return error.Kernel;
        }
        dst.limbs = dst_limbs.?;
    }

    fn len(self: GpuInt, ctx: *c.futhark_context) u64 {
        return @intCast(u64, c.futhark_shape_u64_1d(ctx, self.limbs)[0]);
    }
};

fn pow(ctx: *c.futhark_context, p: GpuInt, inv: GpuInt, one: GpuInt, base: GpuInt, exp: big_int.Const) !GpuInt {
    // const digits = p.len(ctx);
    var result = try GpuInt.clone(ctx, one);
    var x = try GpuInt.clone(ctx, base);
    defer x.deinit(ctx);

    std.debug.print("{}\n", .{exp.limbs.len});

    for (exp.limbs) |limb, i| {
        var lp = limb;
        var j: usize = 0;
        while (j < 64) {
            if (lp & 1 != 0) {

            }

            var x2 = try GpuInt.montgomeryMultiply(ctx, p, inv, x, x);
            std.mem.swap(GpuInt, &x2, &x);
            x2.deinit(ctx);

            lp >>= 1;
            j += 1;
        }
        std.debug.print("{} / {}\n", .{i, exp.limbs.len});
    }

    return result;
}

fn sob(ctx: *c.futhark_context) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const k = 46157;
    const n = 698207;
    const a = 9;

    std.debug.print("Computing initial values...\n", .{});
    var timer = try std.time.Timer.start();

    var @"2^n" = try big_int.Managed.initSet(allocator, 1);
    try @"2^n".shiftLeft(@"2^n", n);

    var big_k_limbs: [1]std.math.big.Limb = undefined;
    var big_k = big_int.Mutable.init(&big_k_limbs, k).toConst();

    var @"2^(n-1)" = try big_int.Managed.initSet(allocator, 1);
    try @"2^(n-1)".shiftLeft(@"2^(n-1)", n - 1);

    var p = try big_int.Managed.init(allocator);
    try p.mul(big_k, @"2^n".toConst());
    try p.addScalar(p.toConst(), 1);

    var x = try big_int.Managed.init(allocator);
    try x.mul(big_k, @"2^(n-1)".toConst());
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    // p will always be larger than x
    const r_digits = try std.math.ceilPowerOfTwo(usize, p.len());
    const digits = 2 * r_digits;

    std.debug.print("p digits: {}\n", .{p.len()});
    std.debug.print("r: 2^{}\n", .{r_digits});
    std.debug.print("work digits: {}\n", .{digits});
    std.debug.print("total bits per int: {}\n", .{digits * 64});

    try p.ensureCapacity(digits);
    for (p.limbs[p.len()..digits]) |*digit| digit.* = 0;

    std.debug.print("Uploading values...\n", .{});
    timer.reset();
    var gpu_a = try GpuInt.initSmallConstant(ctx, digits, a);
    defer gpu_a.deinit(ctx);
    var gpu_p = try GpuInt.init(ctx, @ptrCast([*]const u64, p.limbs.ptr)[0..digits]);
    defer gpu_p.deinit(ctx);
    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Inverting p...\n", .{});
    timer.reset();
    var gpu_p_inv = try GpuInt.montgomeryInvert(ctx, gpu_p);
    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Downloading inverted p...\n", .{});
    timer.reset();
    var p_inv = try big_int.Managed.init(allocator);
    try gpu_p_inv.download(ctx, &p_inv);
    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Computing (-p % p)...\n", .{});
    timer.reset();
    var y = try p.clone();
    y.negate();

    // Need to compute r to get y positive, as Zig only implements rem and not mod.
    var r = try big_int.Managed.initSet(allocator, 1);
    try r.shiftLeft(r, r_digits * 64);
    try y.add(y.toConst(), r.toConst());

    var q = try big_int.Managed.init(allocator);
    var z = try big_int.Managed.init(allocator);
    try q.divTrunc(&z, y.toConst(), p.toConst());

    try z.ensureCapacity(digits);
    for (z.limbs[z.len()..digits]) |*digit| digit.* = 0;
    var gpu_z = try GpuInt.init(ctx, @ptrCast([*]const u64, z.limbs.ptr)[0..digits]);
    defer gpu_z.deinit(ctx);

    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Computing r^2 for p...\n", .{});
    timer.reset();
    var gpu_r2 = try GpuInt.montgomeryComputeR2(ctx, gpu_p, gpu_p_inv, gpu_z);
    defer gpu_r2.deinit(ctx);
    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Converting a into montgomery space...\n", .{});
    timer.reset();
    var gpu_m_a = try GpuInt.montgomeryConvertTo(ctx, gpu_p, gpu_p_inv, gpu_r2, gpu_a);
    defer gpu_m_a.deinit(ctx);
    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Converting 1 into montgomery space...\n", .{});
    timer.reset();
    var gpu_one = try GpuInt.initSmallConstant(ctx, digits, 1);
    defer gpu_one.deinit(ctx);
    var gpu_m_one = try GpuInt.montgomeryConvertTo(ctx, gpu_p, gpu_p_inv, gpu_r2, gpu_one);
    defer gpu_m_one.deinit(ctx);

    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});

    std.debug.print("Computing a^x (mod p)...\n", .{});
    timer.reset();
    var gpu_result = try pow(ctx, gpu_p, gpu_p_inv, gpu_m_one, gpu_m_a, x.toConst());
    defer gpu_result.deinit(ctx);
    try futharkSync(ctx);
    std.debug.print("=> {} us\n", .{timer.lap() / std.time.ns_per_us});


}

fn run(ctx: *c.futhark_context) !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    // const len = 4;
    // try stdout.print("Multiplying integers of {} bits\n", .{len / 2 * 64});

    // const a = try allocator.alloc(u64, len);
    // defer allocator.free(a);
    // for (a) |*i| i.* = 0;

    // const b = try allocator.alloc(u64, len);
    // defer allocator.free(b);
    // for (b) |*i| i.* = 0;

    // for (a[0..len/2]) |*x| x.* = 1;
    // for (b[0..len/2]) |*x| x.* = 1;

    const a = &[_]u64{ 0, 0 };
    const b = &[_]u64{ 1, 0 };

    var futhark_result = blk: {
        var gpu_a = try GpuInt.init(ctx, a);
        defer gpu_a.deinit(ctx);

        var gpu_b = try GpuInt.init(ctx, b);
        defer gpu_b.deinit(ctx);

        var timer = try std.time.Timer.start();

        var gpu_result = try GpuInt.sub(ctx, gpu_a, gpu_b);
        defer gpu_result.deinit(ctx);

        try futharkSync(ctx);

        var elapsed = timer.lap();
        try stdout.print("Futhark elapsed runtime: {}us\n", .{elapsed / std.time.ns_per_us});

        var int = try big_int.Managed.init(allocator);
        errdefer int.deinit();

        try gpu_result.download(ctx, &int);
        break :blk int;
    };
    defer futhark_result.deinit();

    var cpu_result = blk: {
        const cpu_a = std.math.big.int.Const{ .limbs = a, .positive = true };
        const cpu_b = std.math.big.int.Const{ .limbs = b, .positive = true };

        var timer = try std.time.Timer.start();

        var cpu_result = try std.math.big.int.Managed.init(allocator);
        try cpu_result.sub(cpu_a, cpu_b);

        var elapsed = timer.lap();
        try stdout.print("Zig elapsed runtime: {}us\n", .{elapsed / std.time.ns_per_us});

        break :blk cpu_result;
    };
    defer cpu_result.deinit();

    try stdout.print("Results are equal: {}\n", .{futhark_result.eq(cpu_result)});

    // std.debug.print("Futhark result:\n", .{});
    // for (futhark_result.limbs[0 .. futhark_result.len()]) |x| {
    //     std.debug.print("{X}\n", .{ x });
    // }

    // std.debug.print("Bigint result:\n", .{});
    // for (cpu_result.limbs[0 .. cpu_result.len()]) |x| {
    //     std.debug.print("{X}\n", .{ x });
    // }

    std.debug.print("Futhark result: {}\n", .{futhark_result});
    std.debug.print("bigint result: {}\n", .{cpu_result});
}

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();

    const opts = parseOptions() catch {
        try stderr.print("See {s} --help\n", .{std.process.args().nextPosix().?});
        std.os.exit(1);
    };

    if (opts.help) {
        try printHelp();
        return;
    }

    std.debug.print("Initializing...\n", .{});

    const cfg = c.futhark_context_config_new() orelse return error.OutOfMemory;
    defer c.futhark_context_config_free(cfg);

    c.futhark_context_config_set_logging(cfg, @boolToInt(opts.futhark_verbose));
    c.futhark_context_config_set_debugging(cfg, @boolToInt(opts.futhark_debug));

    switch (build_options.futhark_backend) {
        .c => {},
        .multicore => c.futhark_context_config_set_num_threads(cfg, opts.threads),
        .opencl, .cuda => {
            if (opts.device_name) |name| {
                c.futhark_context_config_set_device(cfg, name);
            }

            c.futhark_context_config_set_profiling(cfg, @boolToInt(opts.futhark_profile));
        },
    }

    const ctx = c.futhark_context_new(cfg) orelse return error.OutOfMemory;
    defer c.futhark_context_free(ctx);

    sob(ctx) catch |err| switch (err) {
        error.Kernel, error.Sync => {
            futharkReportError(ctx);
            return error.Kernel;
        },
        else => |e| return e,
    };

    if (opts.futhark_profile) {
        const report = c.futhark_context_report(ctx);
        defer c.free(report);
        try stderr.print("Profile report:\n{s}\n", .{std.mem.spanZ(report)});
    }
}
