const root = @import("root").klib;
const limine = @import("limine");

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

        return mem;
    }

    pub fn malloc(self: *@This(), alloc_type: AllocType, comptime T: type) ?*T {
        return switch (alloc_type) {
            .Bump => self.bump.alloc(type),
            else => unreachable,
        };
    }
};
