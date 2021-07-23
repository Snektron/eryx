const std = @import("std");
const build_options = @import("build_options");
const c = @cImport({
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
            try stderr.print("Error: Unknown option {s}\n", .{arg});
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
        \\--futhark-verbose   Enable futhark logging.
        \\--futhark-debug     Enable futhark debug logging.
        \\
        ++ backend_options
        , .{program_name},
    );
}


pub fn main() !void {
    const opts = parseOptions() catch {
        try std.io.getStdErr().writer().print("See {s} --help\n", .{std.process.args().nextPosix().?});
        std.os.exit(1);
    };

    if (opts.help) {
        try printHelp();
        return;
    }
}
