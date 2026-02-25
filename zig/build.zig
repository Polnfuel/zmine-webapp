const std = @import("std");

pub fn build(b: *std.Build) void {
    const target: std.Build.ResolvedTarget = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const vec = b.addModule("vec", .{
        .root_source_file = b.path("src/vec.zig"),
        .target = target,
    });

    const map = b.addModule("map", .{
        .root_source_file = b.path("src/map.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "vec", .module = vec },
        },
    });

    const stl = b.addModule("stl", .{
        .root_source_file = b.path("src/stl.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "vec", .module = vec },
            .{ .name = "map", .module = map },
        },
    });

    const probs = b.addModule("probs", .{
        .root_source_file = b.path("src/probs.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "stl", .module = stl },
        },
    });

    const exe = b.addExecutable(.{
        .name = "mine-prob",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "stl", .module = stl },
                .{ .name = "probs", .module = probs },
            },
        }),
    });

    exe.rdynamic = true;
    exe.entry = .disabled;
    exe.initial_memory = 4194304;
    exe.max_memory = 16777216;

    const wasm_output = exe.getEmittedBin();
    const copy_wasm = b.addInstallBinFile(wasm_output, "../../../docs/wasm/app.wasm");
    copy_wasm.step.dependOn(&exe.step);

    b.getInstallStep().dependOn(&copy_wasm.step);
}
