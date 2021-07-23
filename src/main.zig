const std = @import("std");
const build_options = @import("build_options");
const c = @cImport({
    @cInclude("malloc.h");
    @cInclude("futhark.h");
});

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
                }
            },
            .opencl => {
                if (std.mem.eql(u8, arg, "--device")) {
                    opts.device_name = it.nextPosix() orelse {
                        try stderr.writeAll("Error: Missing argument <name> for option --device\n");
                        return error.InvalidCmdline;
                    };
                } else if (std.mem.eql(u8, arg, "--futhark-profile")) {
                    opts.futhark_profile = true;
                }
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
        .opencl =>
            \\Available GPU backend options:
            \\--device <name>     Select the Futhark device.
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

pub fn main() !void {
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
        .opencl => {
            if (opts.device_name) |name| {
                c.futhark_context_config_set_device_name(cfg, name);
            }

            futhark_context_config_set_profiling(@boolToInt(opts.futhark_profile));
        },
    }

    const ctx = c.futhark_context_new(cfg) orelse return error.OutOfMemory;
    defer c.futhark_context_free(ctx);

    const input = [_]i32{1, 2, 3, 4};
    const src = c.futhark_new_i32_1d(ctx, &input, @intCast(i64, input.len)) orelse return error.OutOfMemory;
    defer _ = c.futhark_free_i32_1d(ctx, src);

    var dst: ?*c.futhark_i32_1d = null;
    defer if (dst) |arr| {
        _ = c.futhark_free_i32_1d(ctx, arr);
    };

    var err = c.futhark_entry_main(ctx, &dst, src);
    err |= c.futhark_context_sync(ctx);
    if (err != 0) {
        return error.KernelFailed;
    }

    const len = c.futhark_shape_i32_1d(ctx, dst)[0];
    const host_dst = try std.heap.page_allocator.alloc(i32, @intCast(usize, len));
    _ = c.futhark_values_i32_1d(ctx, dst, host_dst.ptr);

    try stdout.writeAll("Results:\n");
    for (host_dst) |value| {
        try stdout.print("{} ", .{value});
    }
    try stdout.writeByte('\n');

    if (opts.futhark_profile) {
        const report = c.futhark_context_report(ctx);
        defer c.free(report);
        try stderr.print("Profile report:\n{s}\n", .{std.mem.spanZ(report)});
    }
}
