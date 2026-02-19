const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const Step = Build.Step;
const StepMakeOptions = Step.MakeOptions;
const StepCompile = Step.Compile;
const Module = Build.Module;

// TODO: module export
// TODO: tests
// TODO: linux builds (see: castholm/SDL_linux_deps)

pub fn build(b: *std.Build) void {
    const opts: GlobalOptions = .Init(b);

    const libgu = export_module(b, "libgu", "src/gu.zig");

    const example = bin_example(b, &opts, libgu);
    step_example(b, example, &opts);
    step_example_run(b, example);

    step_clean(b);
}

fn export_module(b: *Build, name: []const u8, path: []const u8) *Module {
    return b.addModule(name, .{ .root_source_file = b.path(path) });
}

// EXAMPLE APP

fn bin_example(b: *Build, opts: *const GlobalOptions, libgu: *Module) *StepCompile {
    const bin = b.addExecutable(.{
        .name = "gu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            //.imports = imports, // []const Build.Module.Import
            .target = opts.Target,
            .optimize = opts.Optimize,
            .strip = opts.Strip,
        }),
    });

    bin.root_module.addImport("libgu", libgu);

    const module_opts = .{ .target = opts.Target, .optimize = opts.Optimize, .strip = opts.Strip };
    if (b.lazyDependency("sdl", module_opts)) |dep| {
        const sdl_lib = dep.artifact("SDL3");
        bin.root_module.linkLibrary(sdl_lib);
    }

    const assets = [_]struct { []const u8, []const u8 }{
        .{ "font-notomono-lod-black", "assets/font-notomono-lod-black.bmp" },
        .{ "font-notomono-lod", "assets/font-notomono-lod.bmp" },
        .{ "font-departuremono", "assets/font-departuremono.bmp" },
        .{ "font-nameheremono", "assets/font-nameheremono.bmp" },
        .{ "font-nameheremono-bold", "assets/font-nameheremono-bold.bmp" },
        .{ "font-mago3mono", "assets/font-mago3mono.bmp" },
        .{ "yuriko1", "assets/yuriko1.bmp" },
        .{ "yuriko2", "assets/yuriko2.bmp" },
    };
    for (assets) |asset|
        bin.root_module.addAnonymousImport(asset[0], .{ .root_source_file = b.path(asset[1]) });

    return bin;
}

fn step_example(
    b: *Build,
    bin: *StepCompile,
    opts: *const GlobalOptions,
) void {
    const step = b.step("example", "Build the example app");

    if (opts.NoBin) {
        step.dependOn(&bin.step);
    } else {
        const install = b.addInstallArtifact(bin, .{});
        step.dependOn(&install.step);
    }
}

fn step_example_run(b: *Build, bin: *StepCompile) void {
    const step = b.step("example-run", "Build and run the example app");

    const command = b.addRunArtifact(bin);
    if (b.args) |args| command.addArgs(args);

    step.dependOn(&command.step);
}

// CLEANUP / BUILD UTIL

fn step_clean(b: *Build) void {
    const step = b.step("clean", "Remove build system artifacts");

    step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = b.install_path }).step);

    if (builtin.os.tag != .windows) {
        step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = ".zig-cache" }).step);
    } else {
        step.makeFn = CleanWindows;
    }
}

fn CleanWindows(_: *Step, _: StepMakeOptions) anyerror!void {
    // Windows locks `.zig-cache` during build, so we have to clean it outside the build system
    std.log.err("Cannot remove `.zig-cache` during build process on Windows. Run `./clean.bat`", .{});
}

// GLOBAL OPTIONS

/// Common options for this build script
const GlobalOptions = struct {
    Target: ResolvedTarget,
    Optimize: OptimizeMode,
    NoBin: bool,
    Strip: bool,

    pub fn Init(b: *Build) GlobalOptions {
        return .{
            .Target = b.standardTargetOptions(.{}),
            .Optimize = b.standardOptimizeOption(.{}),
            .NoBin = b.option(bool, "no-bin", "skip emitting binary") orelse false,
            .Strip = b.option(bool, "strip", "strip the binary") orelse false,
        };
    }
};
