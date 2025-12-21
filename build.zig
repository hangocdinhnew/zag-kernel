const std = @import("std");

fn targetQuery(os: ?std.Target.Os.Tag) std.Target.Query {
    const query: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = os,
        .abi = .none,
    };

    return query;
}

pub fn build(b: *std.Build) void {
    const kernel_query = targetQuery(.freestanding);

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

    const limine_module = b.createModule(.{
        .root_source_file = b.path("src/limine.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });

    limine_module.addIncludePath(b.path("3rd/limine-protocol/include"));
    kernellib_module.addImport("limine", limine_module);

    kernel_module.addImport("klib", kernellib_module);
    kernel_module.addImport("limine", limine_module);

    kernel_module.red_zone = false;
    kernel_module.code_model = .kernel;

    kernellib_module.red_zone = false;
    kernellib_module.code_model = .kernel;

    const kernel = b.addExecutable(.{
        .name = "zag-kernel",
        .root_module = kernel_module,
    });

    kernel.setLinkerScript(b.path("linker.lds"));

    b.installArtifact(kernel);
}
