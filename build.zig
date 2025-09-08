const std = @import("std");

const Arch = enum {
    x86_64,
    aarch64,

    fn toStd(self: @This()) std.Target.Cpu.Arch {
        return switch (self) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
        };
    }
};

fn targetQueryForArch(arch: Arch, os: ?std.Target.Os.Tag) std.Target.Query {
    var query: std.Target.Query = .{
        .cpu_arch = arch.toStd(),
        .os_tag = os,
        .abi = .none,
    };

    switch (arch) {
        .x86_64 => {
            const Target = std.Target.x86;

            query.cpu_features_add = Target.featureSet(&.{ .popcnt, .soft_float });
            query.cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx });
        },
        .aarch64 => {
            const Target = std.Target.aarch64;

            query.cpu_features_add = Target.featureSet(&.{});
            query.cpu_features_sub = Target.featureSet(&.{ .fp_armv8, .crypto, .neon });
        },
    }

    return query;
}

pub fn build(b: *std.Build) void {
    const arch = b.option(Arch, "arch", "Architectue to build the kernel for") orelse .x86_64;
    const bootloader_query = targetQueryForArch(arch, .uefi);

    const bootloader_target = b.resolveTargetQuery(bootloader_query);
    const optimize = b.standardOptimizeOption(.{});

    const bootloader = b.addExecutable(.{
        .name = "ziggy_bootloader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bootloader/main.zig"),
            .target = bootloader_target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    b.installArtifact(bootloader);
}
