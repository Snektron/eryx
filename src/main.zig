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
        ++ backend_options
        , .{program_name},
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

    fn init(ctx: *c.futhark_context, limbs: []u64) !GpuInt {
        std.debug.assert(std.math.isPowerOfTwo(limbs.len));

        const gpu_limbs = c.futhark_new_u64_1d(ctx, limbs.ptr, @intCast(i64, limbs.len)) orelse return error.OutOfMemory;
        try futharkSync(ctx);
        return GpuInt{.limbs = gpu_limbs};
    }

    fn initRaw(ctx: *c.futhark_context, limbs: *c.futhark_u64_1d) GpuInt {
        const self =  GpuInt{.limbs = limbs};
        std.debug.assert(std.math.isPowerOfTwo(self.len(ctx)));
        return self;
    }

    fn fromConst(ctx: *c.futhark_context, int: big_int.Const) !GpuInt {
        std.debug.assert(int.positive);
        return initSet(ctx, int.limbs);
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
        int.normalize(int.limbs.len);
    }

    fn invokeBinaryKernel(comptime kernel: anytype, ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        var dst: ?*c.futhark_u64_1d = null;
        errdefer if (dst) |ptr| {
            _ = c.futhark_free_u64_1d(ctx, ptr);
        };

        const err = kernel(ctx, &dst, a.limbs, b.limbs);
        if (err != 0) {
            return error.Kernel;
        }

        try futharkSync(ctx);
        return initRaw(ctx, dst.?);
    }

    fn add(ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeBinaryKernel(c.futhark_entry_add, ctx, a, b);
    }

    fn sub(ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeBinaryKernel(c.futhark_entry_sub, ctx, a, b);
    }

    fn mul(ctx: *c.futhark_context, a: GpuInt, b: GpuInt) !GpuInt {
        return try invokeBinaryKernel(c.futhark_entry_mul, ctx, a, b);
    }

    fn len(self: GpuInt, ctx: *c.futhark_context) u64 {
        return @intCast(u64, c.futhark_shape_u64_1d(ctx, self.limbs)[0]);
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const opts = parseOptions() catch {
        try stderr.print("See {s} --help\n", .{std.process.args().nextPosix().?});
        std.os.exit(1);
    };

    if (opts.help) {
        try printHelp();
        return;
    }

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

    const len = 1 << 20;
    try stdout.print("Multiplying integers of {} bits\n", .{len / 2 * 64});

    const a = try allocator.alloc(u64, len);
    defer allocator.free(a);
    for (a) |*i| i.* = 0;

    const b = try allocator.alloc(u64, len);
    defer allocator.free(b);
    for (b) |*i| i.* = 0;

    for (a[0..len / 2]) |*x, i| x.* = ~i;
    for (b[0..len / 2]) |*x, i| x.* = ~i;

    var futhark_result = blk: {
        var gpu_a = try GpuInt.init(ctx, a);
        defer gpu_a.deinit(ctx);

        var gpu_b = try GpuInt.init(ctx, b);
        defer gpu_b.deinit(ctx);

        var timer = try std.time.Timer.start();

        var gpu_result = GpuInt.mul(ctx, gpu_a, gpu_b) catch |err| switch (err) {
            error.Kernel, error.Sync => {
                futharkReportError(ctx);
                return error.Kernel;
            },
            else => |e| return e,
        };
        defer gpu_result.deinit(ctx);

        var elapsed = timer.lap();
        try stdout.print("Futhark elapsed runtime: {}us\n", .{ elapsed / std.time.ns_per_us });

        var int = try big_int.Managed.init(allocator);
        errdefer int.deinit();

        try gpu_result.download(ctx, &int);
        break :blk int;
    };
    defer futhark_result.deinit();

    var cpu_result = blk: {
        const cpu_a = std.math.big.int.Const{.limbs = a, .positive = true};
        const cpu_b = std.math.big.int.Const{.limbs = b, .positive = true};

        var timer = try std.time.Timer.start();

        var cpu_result = try std.math.big.int.Managed.init(allocator);
        try cpu_result.mul(cpu_a, cpu_b);

        var elapsed = timer.lap();
        try stdout.print("Zig elapsed runtime: {}us\n", .{ elapsed / std.time.ns_per_us });

        break :blk cpu_result;
    };
    defer cpu_result.deinit();

    try stdout.print("Results are equal: {}\n", .{ futhark_result.eq(cpu_result) });

    // std.debug.print("Futhark result:\n", .{});
    // for (futhark_result.limbs[0 .. futhark_result.len()]) |x| {
    //     std.debug.print("{X}\n", .{ x });
    // }

    // std.debug.print("CPU result:\n", .{});
    // for (cpu_result.limbs[0 .. cpu_result.len()]) |x| {
    //     std.debug.print("{X}\n", .{ x });
    // }

    // std.debug.print("Futhark result: {}\n", .{ futhark_result });
    // std.debug.print("bigint result: {}\n", .{ cpu_result });

    if (opts.futhark_profile) {
        const report = c.futhark_context_report(ctx);
        defer c.free(report);
        try stderr.print("Profile report:\n{s}\n", .{std.mem.spanZ(report)});
    }
}
