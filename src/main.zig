pub const klib = @import("klib");
pub const builtin = @import("builtin");
pub const std = @import("std");
const limine = @import("limine");

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    klib.utils.hcf();
}

const LIMINE_COMMON_MAGIC1: usize = 0xc7b1dd30df4c8b88;
const LIMINE_COMMON_MAGIC2: usize = 0x0a82e883a194f07b;

pub export var base_revision: [3]u64 linksection(".limine_requests") = [3]u64{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 6 };

pub export var hhdm_request: limine.limine_hhdm_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_COMMON_MAGIC1, LIMINE_COMMON_MAGIC2, 0x48dcf1cb8ad2b852, 0x63984e959a98244b },
    .revision = 0,
};

pub export var memmap_request: limine.limine_memmap_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_COMMON_MAGIC1, LIMINE_COMMON_MAGIC2, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62 },
    .revision = 0,
};

pub export var start_marker: [4]u64 linksection(".limine_requests_start") = [4]u64{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub export var end_marker: [2]u64 linksection(".limine_requests_end") = [2]u64{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };

export fn _start() noreturn {
    if (builtin.cpu.arch == .x86_64) {
        klib.enable_sse();
        if (builtin.cpu.has(.x86, .avx)) klib.enable_avx();
    }

    klib.check_base_rev(base_revision);

    if (hhdm_request.response) |response| {
        klib.lmBase = response.*.offset;
    } else @panic("No linear mapping, cannot continue execution.");

    var usable_memory_size: usize = 0;
    var suitable_region_base: usize = 0;
    var metadata_size: usize = 0;

    if (memmap_request.response) |response| {
        const entry_count = response.*.entry_count;
        for (0..entry_count) |i| {
            const entry = response.*.entries[i];
            const entry_length = entry.*.length;
            const entry_type = entry.*.type;

            if (entry_type != limine.LIMINE_MEMMAP_USABLE)
                continue;

            usable_memory_size +%= entry_length;
        }

        metadata_size = (usable_memory_size / klib.PAGE_SIZE) * @sizeOf(klib.Page);

        if (usable_memory_size < metadata_size) @panic("OOM, cannot continue execution.");

        for (0..entry_count) |i| {
            const entry = response.*.entries[i];
            const entry_base = entry.*.base;
            const entry_length = entry.*.length;
            const entry_type = entry.*.type;

            if (entry_type != limine.LIMINE_MEMMAP_USABLE)
                continue;

            if (entry_length >= metadata_size) {
                suitable_region_base = entry_base;
                break;
            }
        }
    } else @panic("No memory map, cannot continue execution.");

    const metadata = @as([*]u8, @ptrFromInt(suitable_region_base + klib.lmBase))[0..metadata_size];
    var metadata_fba = std.heap.FixedBufferAllocator.init(metadata);
    const metadata_allocator = metadata_fba.allocator();

    klib.page_metadata_array = metadata_allocator.alloc(
        klib.Page,
        usable_memory_size / klib.PAGE_SIZE,
    ) catch @panic("OOM, cannot continue execution.");

    klib.utils.hcf();
}
