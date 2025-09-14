const limine = @import("limine");
const root = @import("root").klib;

pub const BumpAllocator = struct {
    base: usize,
    top: usize,
    end: usize,

    pub fn init(entry_usable: ?*volatile limine.memmap_entry) @This() {
        const entry_usable_ptr = entry_usable.?;
        var bump: @This() = undefined;

        bump.base = entry_usable_ptr.base;
        bump.top = entry_usable_ptr.base;
        bump.end = entry_usable_ptr.base + entry_usable_ptr.length;

        return bump;
    }

    pub fn alloc(self: *@This(), comptime T: type) ?*T {
        const size = @sizeOf(T);
        const @"align" = @alignOf(T);

        const ptr: *T = (self.top + (@"align" - 1)) & ~(@"align" - 1);

        if (ptr + size > self.end)
            root.utils.hcf();

        if (ptr + size > self.end) {
            return null;
        }

        self.top = ptr + size;

        return ptr;
    }
};
