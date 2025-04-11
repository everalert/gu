const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "galeforce-ui",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // TODO: place behind 'example' step
    const sdl_dep = b.lazyDependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    if (sdl_dep) |dep| {
        const sdl_lib = dep.artifact("SDL3");
        exe.root_module.linkLibrary(sdl_lib);
    }

    exe.root_module.addAnonymousImport("ascii-font", .{
        .root_source_file = b.path("assets/ascii.bmp"),
    });
    exe.root_module.addAnonymousImport("corner-round", .{
        .root_source_file = b.path("assets/corner-round.bmp"),
    });
    exe.root_module.addAnonymousImport("corner-angular", .{
        .root_source_file = b.path("assets/corner-angular.bmp"),
    });
    exe.root_module.addAnonymousImport("corner-beveled", .{
        .root_source_file = b.path("assets/corner-beveled.bmp"),
    });

    b.installArtifact(exe);

    // run step
    // TODO: maybe also place this behind 'example' step?

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args|
        run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
