const root = @import("root").klib;
const limine = @import("limine");

const log = root.log;

pub const map = @import("mem/map.zig");
pub const alloc = @import("mem/alloc.zig");

pub const AllocType = enum {
    Bump,
};

pub const Mem = struct {
    map: map.Memmap,
    bump: alloc.BumpAllocator,

    pub fn init(request: limine.memmap_request) @This() {
        var mem: @This() = undefined;

        mem.map = map.Memmap.init(request);
        mem.bump = alloc.BumpAllocator.init(mem.map.entry_usable);

        log.log(.Info, "Memory initialized!\n", .{});

        return mem;
    }

    pub fn malloc(self: *@This(), alloc_type: AllocType, comptime T: type) ?*T {
        log.log(.Debug, "Malloc called!\n", .{});

        return switch (alloc_type) {
            .Bump => {
                log.log(.Debug, "Allocating data using Bump allocator...\n", .{});
                return self.bump.alloc(T);
            },
        };
    }
};
