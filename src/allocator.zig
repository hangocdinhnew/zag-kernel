const std = @import("std");
const root = @import("root").klib;

// From https://ziglang.org/documentation/0.15.2/std/#std.heap.page_allocator

pub fn map(n: usize, alignment: std.mem.Alignment) ?[*]u8 {
    const page_size = root.mem.PAGE_SIZE;

    if (alignment.toByteUnits() > page_size)
        @panic("alignment > page size not supported");

    const pages = root.mem.alignUp(n, page_size) / page_size;
    return @ptrCast(root.vmm.kalloc_pages(pages));
}

fn alloc(context: *anyopaque, n: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
    _ = context;
    _ = ra;
    std.debug.assert(n > 0);
    return map(n, alignment);
}

fn realloc(
    uncasted_memory: []u8,
    new_len: usize,
    may_move: bool,
) ?[*]u8 {
    return root.vmm.realloc(uncasted_memory, new_len, may_move);
}

pub fn unmap(memory: []align(root.mem.PAGE_SIZE) u8) void {
    root.vmm.kfree_pages(@ptrCast(memory.ptr));
}

fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
    _ = context;
    _ = alignment;
    _ = return_address;
    return realloc(memory, new_len, false) != null;
}

fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    _ = context;
    _ = alignment;
    _ = return_address;
    return realloc(memory, new_len, true);
}

fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
    _ = context;
    _ = alignment;
    _ = return_address;
    return unmap(@alignCast(memory));
}

pub const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

pub const page_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};
