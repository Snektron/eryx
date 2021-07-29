const std = @import("std");
const Builder = std.build.Builder;

const FutharkBackend = enum {
    c,
    multicore,
    opencl,
    cuda,
};

fn addFutharkSrc(b: *Builder, exe: *std.build.LibExeObjStep, backend: FutharkBackend) void {
    const cache_root = std.fs.path.join(b.allocator, &[_][]const u8{
        b.build_root,
        b.cache_root
    }) catch unreachable;

    const futhark_output = std.fs.path.join(b.allocator, &[_][]const u8{
        cache_root,
        "futhark"
    }) catch unreachable;

    const futhark_gen = b.addSystemCommand(&[_][]const u8{
        "futhark",
        std.meta.tagName(backend),
        "--library",
        "src/main.fut",
        "-o",
        futhark_output
    });

    exe.step.dependOn(&futhark_gen.step);

    const futhark_c_output = std.mem.concat(b.allocator, u8, &[_][]const u8{futhark_output, ".c"}) catch unreachable;
    exe.addCSourceFile(futhark_c_output, &[_][]const u8{"-fno-sanitize=undefined"});
    exe.addIncludeDir(cache_root);
    exe.addBuildOption(FutharkBackend, "futhark_backend", backend);
}

pub fn build(b: *std.build.Builder) void {
     const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const backend = b.option(FutharkBackend, "futhark-backend", "Set futhark backend") orelse .c;
    const ocl_inc = b.option([]const u8, "opencl-include", "opencl include path") orelse "/usr/include";
    const ocl_lib = b.option([]const u8, "opencl-lib", "opencl library path") orelse "/usr/lib";
    const cuda_inc = b.option([]const u8, "cuda-include", "opencl include path") orelse "/usr/local/cuda/include";
    const cuda_lib = b.option([]const u8, "cuda-lib", "opencl library path") orelse "/usr/local/cuda/lib64";

    const exe = b.addExecutable("gpu-big-int", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.linkLibC();
    if (backend == .opencl) {
        exe.addSystemIncludeDir(ocl_inc);
        exe.addLibPath(ocl_lib);
        exe.linkSystemLibraryName("OpenCL");
    } else if (backend == .cuda) {
        exe.addSystemIncludeDir(cuda_inc);
        exe.addLibPath(cuda_lib);
        exe.linkSystemLibraryName("cuda");
        exe.linkSystemLibraryName("cudart");
        exe.linkSystemLibraryName("nvrtc");
    }
    
    addFutharkSrc(b, exe, backend);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
