const std = @import("std");

const ZagArch = enum {
    x86_64,
    aarch64,

    fn toStd(self: @This()) std.Target.Cpu.Arch {
        return switch (self) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
        };
    }
};

fn targetQuery(arch: ?std.Target.Cpu.Arch) std.Target.Query {
    var query: std.Target.Query = .{
        .cpu_arch = arch,
        .os_tag = .freestanding,
        .abi = .none,
    };

    switch (arch.?) {
        .x86_64 => {
            const Target = std.Target.x86;

            query.cpu_features_add = Target.featureSet(&.{.soft_float});
            query.cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx });
        },

        .aarch64 => {
            const Target = std.Target.aarch64;

            query.cpu_features_add = Target.featureSet(&.{});
            query.cpu_features_sub = Target.featureSet(&.{ .fp_armv8, .crypto, .neon });
        },

        else => unreachable,
    }

    return query;
}

pub fn build(b: *std.Build) void {
    const arch = b.option(ZagArch, "arch", "The target architecture of Zag") orelse .x86_64;

    const kernel_query = targetQuery(arch.toStd());

    const kernel_target = b.resolveTargetQuery(kernel_query);
    const optimize = b.standardOptimizeOption(.{});

    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });

    const kernellib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });

    const limine_cimport = b.addTranslateC(.{
        .root_source_file = b.path("thirdparty/limine-protocol/include/limine.h"),
        .target = kernel_target,
        .optimize = optimize,
        .link_libc = false,
    });
    const limine_module = limine_cimport.createModule();

    kernellib_module.addImport("limine", limine_module);
    kernellib_module.addImport("klib", kernellib_module);

    kernel_module.addImport("klib", kernellib_module);
    kernel_module.addImport("limine", limine_module);

    if (arch == .x86_64) {
        kernel_module.code_model = .kernel;
        kernel_module.red_zone = false;
    } else {
        kernel_module.code_model = .default;
    }

    const kernel = b.addExecutable(.{
        .name = "zag-kernel",
        .root_module = kernel_module,
        .use_llvm = true,
    });

    kernel.setLinkerScript(b.path(b.fmt("linker-{s}.lds", .{@tagName(arch)})));

    b.installArtifact(kernel);
}
