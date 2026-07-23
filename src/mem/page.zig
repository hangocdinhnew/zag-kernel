const limine = @import("limine");
const root = @import("klib");
const std = @import("std");

pub const PAGE_SIZE = 4096;

pub const PageFlags = packed struct(u8) {
    free: bool = false,
    reserved: bool = false,
    _: u6 = 0,
};

pub const Page = struct {
    flags: PageFlags = .{},

    info: union {
        buddy: struct {
            prev: ?*Page = null,
            next: ?*Page = null,
            order: usize = 0,
        },
    } = .{
        .buddy = .{},
    },
};

pub const PageInfo = struct {
    const Self = @This();

    infoArray: ?[]Page = null,

    pub fn init(self: *Self, response: *limine.limine_memmap_response) void {
        var memory_size: usize = 0;
        var suitable_region_base: usize = 0;
        var metadata_size: usize = 0;

        const entry_count = response.*.entry_count;
        for (0..entry_count) |i| {
            const entry = response.*.entries[i];
            const entry_length = entry.*.length;

            memory_size += entry_length;
        }

        metadata_size = (memory_size / PAGE_SIZE) * @sizeOf(Page);

        if (memory_size < metadata_size) @panic("OOM, cannot continue execution.");

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

        const metadata = @as([*]u8, @ptrFromInt(suitable_region_base + root.lmBase))[0..metadata_size];
        var metadata_fba = std.heap.FixedBufferAllocator.init(metadata);
        const metadata_allocator = metadata_fba.allocator();

        self.infoArray = metadata_allocator.alloc(
            Page,
            memory_size / PAGE_SIZE,
        ) catch @panic("OOM, cannot continue execution.");

        const infoArray = self.infoArray orelse @panic("BUG, infoArray not initialized.");

        @memset(infoArray, .{});

        for (0..entry_count) |i| {
            const entry = response.*.entries[i];
            if (entry.*.type == limine.LIMINE_MEMMAP_USABLE)
                continue;

            const start_page: usize = std.math.divFloor(usize, entry.*.base, PAGE_SIZE) catch unreachable;
            const end_page: usize = std.math.divCeil(usize, entry.*.base + entry.*.length, PAGE_SIZE) catch unreachable;

            for (start_page..end_page) |page| {
                infoArray[page].flags.reserved = true;
            }
        }

        const metadata_start_page = std.math.divFloor(
            usize,
            suitable_region_base,
            PAGE_SIZE,
        ) catch unreachable;

        const metadata_end_page = std.math.divCeil(
            usize,
            suitable_region_base + metadata_size,
            PAGE_SIZE,
        ) catch unreachable;

        for (metadata_start_page..metadata_end_page) |page| {
            infoArray[page].flags.reserved = true;
        }
    }
};
