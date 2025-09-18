const root = @import("root").klib;
const limine = @import("limine");

pub const map = @import("mem/map.zig");
pub const alloc = @import("mem/alloc.zig");

pub const AllocType = enum {
    Bump,
};

pub const Mem = struct {
    logger: *const root.log.Logger,
    map: map.Memmap,
    bump: alloc.BumpAllocator,

    pub fn init(request: limine.memmap_request, logger: *const root.log.Logger) @This() {
        var mem: @This() = undefined;

        mem.logger = logger;
        mem.map = map.Memmap.init(request, mem.logger);
        mem.bump = alloc.BumpAllocator.init(mem.map.entry_usable, mem.logger);

        mem.logger.log(.Info, "Memory initialized!\n");

        return mem;
    }

    pub fn malloc(self: *@This(), alloc_type: AllocType, comptime T: type) ?*T {
        self.logger.log(.Debug, "Malloc called!\n");

        return switch (alloc_type) {
            .Bump => {
                self.logger.log(.Debug, "Allocating data using Bump allocator...\n");
                return self.bump.alloc(T);
            },
        };
    }
};
