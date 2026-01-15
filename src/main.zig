pub const klib = @import("klib");
pub const builtin = @import("builtin");
pub const std = @import("std");
const limine = @import("limine");

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
    .logFn = klogfn,
};

pub fn klogfn(
    comptime level: std.log.Level,
    comptime _: @Type(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) >= @intFromEnum(std.log.Level.debug)) return;

    const prefix = "[" ++ comptime level.asText() ++ "]: ";

    klib.kprint(prefix ++ fmt ++ "\n", args);
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    @branchHint(.cold);

    std.log.err(
        \\PANIC! Error message:
        \\{s}
    , .{msg});

    klib.utils.hcf();
}

const LIMINE_MAGIC1 = 0xc7b1dd30df4c8b88;
const LIMINE_MAGIC2 = 0x0a82e883a194f07b;

pub export var start_marker: [4]u64 linksection(".limine_requests_start") = [4]u64{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub export var end_marker: [2]u64 linksection(".limine_requests_end") = [2]u64{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };
pub export var base_revision: [3]u64 linksection(".limine_requests") = [3]u64{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3 };

pub export var memmap_request: limine.memmap_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_MAGIC1, LIMINE_MAGIC2, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62 },
    .revision = 0,
};

pub export var framebuffer_request: limine.framebuffer_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_MAGIC1, LIMINE_MAGIC2, 0x9d5827dcd881dd75, 0xa3148604f6fab11b },
    .revision = 0,
};

export fn _start() noreturn {
    klib.check_base_rev(base_revision);

    if (builtin.cpu.arch == .x86_64) {
        klib.enable_sse();
        if (builtin.cpu.has(.x86, .avx)) klib.enable_avx();
    }

    klib.uart.init(klib.UARTSpeed.fromBaudrate(9600).?);

    std.log.info("Hello, World!", .{});

    klib.gdt.init();
    klib.idt.init();

    if (memmap_request.response == null) {
        @panic("Failed to get memory map!");
    }

    var usable_base: u64 = 0;
    var usable_length: u64 = 0;

    const response = memmap_request.response;
    for (0..response.*.entry_count) |i| {
        const entry = response.*.entries[i];

        if (entry.*.type == limine.MEMMAP_USABLE) {
            usable_base = entry.*.base;
            usable_length = entry.*.length;
        }
    }

    if (usable_base == 0 or usable_length == 0) @panic("Failed to find usable memory!");
    var frame_alloc = klib.mem.FrameAllocator.init();
    const interface = &frame_alloc;

    interface.setbootinfo(usable_base, usable_length);

    const test_va = klib.mem.VirtualAddress.from(0xffff_8000_0000_0000);
    const test_frame = interface.alloc(0) orelse @panic("OOM allocating test frame");

    klib.mem.kmap(test_va, test_frame, .{}, interface);

    const lmao: *u8 = @ptrFromInt(test_va.to());

    std.log.info("I SURVIVED!", .{});

    lmao.* = 'c';

    std.log.info("NO WAY: {c}", .{lmao.*});

    const ptr: *volatile u64 = @ptrFromInt(0xffff_8000_0000_0000);
    ptr.* = 'a';

    klib.utils.hcf();
}
