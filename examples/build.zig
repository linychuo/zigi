const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigi_mod = b.addModule("zigi", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "../src/zigi.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zigi", zigi_mod);

    const exe = b.addExecutable(.{
        .name = "zigi-example",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);
}