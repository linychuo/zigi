const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zigi-test",
        .root_source_file = .{ .src_path = "test_fixes.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zigi_mod = b.addModule("zigi", .{
        .root_source_file = .{ .src_path = "src/zigi.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigi", zigi_mod);

    b.installArtifact(exe);
}