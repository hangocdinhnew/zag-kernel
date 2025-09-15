const limine = @import("limine");
const root = @import("root").klib;

pub const BumpAllocator = struct {
    base: usize,
    top: usize,
    end: usize,

    pub fn init(entry: ?*volatile limine.memmap_entry) @This() {
        const entry_ptr = entry.?;
        var bump: @This() = undefined;

        bump.base = entry_ptr.base;
        bump.top = entry_ptr.base;
        bump.end = entry_ptr.base + entry_ptr.length;

        return bump;
    }

    pub fn alloc(self: *@This(), comptime T: type) ?*T {
        const size = @sizeOf(T);
        const @"align" = @alignOf(T);

        const ptr: *T = (self.top + (@"align" - 1)) & ~(@"align" - 1);

        if (ptr + size > self.end) {
            return null;
        }

        self.top = ptr + size;

        return ptr;
    }
};
