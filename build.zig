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

            query.cpu_features_add = Target.featureSet(&.{ .sse, .sse2, .mmx, .x87, .cx8 });
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
    const kernel_query = targetQueryForArch(arch, .freestanding);

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

    kernellib_module.addIncludePath(b.path("3rd/limine-protocol/include"));

    kernel_module.addImport("klib", kernellib_module);

    switch (arch) {
        .x86_64 => {
            kernel_module.red_zone = false;
            kernel_module.code_model = .kernel;

            kernellib_module.red_zone = false;
            kernellib_module.code_model = .kernel;
        },
        .aarch64 => {},
    }

    const kernel = b.addExecutable(.{
        .name = "ziggy_kernel",
        .root_module = kernel_module,
    });

    kernel.setLinkerScript(b.path(b.fmt("linker-{s}.lds", .{@tagName(arch)})));

    b.installArtifact(kernel);
}
