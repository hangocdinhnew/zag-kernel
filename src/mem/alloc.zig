const limine = @import("limine");
const root = @import("root").klib;

pub const BumpAllocator = struct {
    base: usize,
    top: usize,
    end: usize,
    logger: *const root.log.Logger,

    pub fn init(entry: ?*volatile limine.memmap_entry, logger: *const root.log.Logger) @This() {
        const entry_ptr = entry.?;
        var bump: @This() = undefined;

        bump.base = entry_ptr.base;
        bump.top = entry_ptr.base;
        bump.end = entry_ptr.base + entry_ptr.length;
        bump.logger = logger;

        bump.logger.log(.Info, "Bump allocator initialized!\n");

        return bump;
    }

    pub fn alloc(self: *@This(), comptime T: type) ?*T {
        self.logger.log(.Debug, "Bump allocator called!");

        const size: usize = @sizeOf(T);
        const @"align": usize = @alignOf(T);

        const ptr: *T = @ptrFromInt(@as(u64, self.top + (@"align" - 1)) & ~(@"align" - 1));

        if (@intFromPtr(ptr) + size > self.end) {
            return null;
        }

        self.top = @intFromPtr(ptr) + size;

        return ptr;
    }
};
