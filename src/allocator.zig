const std = @import("std");
const root = @import("root").klib;

const Region = struct {
    start: usize,
    pages: usize,
    next: ?*Region,
};

var region_head: ?*Region = null;
var alloc_lock = root.smp.Spinlock{};

fn alloc_region() ?*Region {
    const frame = root.vmm.frame_alloc.alloc(0) orelse return null;
    const ptr: ?*Region = @ptrFromInt(root.vmm.physToVirt(frame.to()));
    return ptr;
}

fn free_region(region: *Region) void {
    const phys = root.vmm.virtToPhys(@intFromPtr(region));
    root.vmm.frame_alloc.free(root.mem.PhysFrame.from(phys), 0);
}

fn insert_region(region: *Region) void {
    if (region_head == null or region.start < region_head.?.start) {
        region.next = region_head;
        region_head = region;
        return;
    }

    var cur = region_head.?;
    while (cur.next) |n| {
        if (region.start < n.start) break;
        cur = n;
    }

    region.next = cur.next;
    cur.next = region;
}

fn find_region(addr: usize) ?*Region {
    var cur = region_head;
    while (cur) |r| {
        if (r.start == addr) return r;
        cur = r.next;
    }
    return null;
}

fn remove_region(region: *Region) void {
    if (region_head == region) {
        region_head = region.next;
        return;
    }

    var cur = region_head;
    while (cur) |r| {
        if (r.next == region) {
            r.next = region.next;
            return;
        }
        cur = r.next;
    }
}

fn find_free_range(pages: usize) usize {
    const size = pages * root.mem.PAGE_SIZE;
    var addr: usize = root.KERNEL_HEAP_START;

    var cur = region_head;
    while (cur) |r| {
        if (addr + size <= r.start)
            return addr;

        addr = r.start + r.pages * root.mem.PAGE_SIZE;
        cur = r.next;
    }

    return addr;
}

pub fn map(n: usize, alignment: std.mem.Alignment) ?[*]u8 {
    const page_size = root.mem.PAGE_SIZE;

    if (alignment.toByteUnits() > page_size)
        @panic("alignment > page size not supported");

    const pages =
        root.mem.alignUp(n, page_size) / page_size;

    alloc_lock.lock();
    defer alloc_lock.unlock();

    const base = find_free_range(pages);

    const region = alloc_region() orelse return null;
    region.* = .{
        .start = base,
        .pages = pages,
        .next = null,
    };
    insert_region(region);

    var i: usize = 0;
    while (i < pages) : (i += 1) {
        const frame = root.vmm.frame_alloc.alloc(0) orelse {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                const vaddr = base + j * page_size;
                const phys = root.vmm.unmap_page(vaddr) orelse continue;
                root.vmm.frame_alloc.free(
                    root.mem.PhysFrame.from(phys),
                    0,
                );
            }
            remove_region(region);
            free_region(region);
            return null;
        };

        root.vmm.map_page(
            base + i * page_size,
            frame.to(),
            .{
                .rw = true,
                .global = true,
                .nx = true,
            },
        );
    }

    root.vmm.flush_all();
    return @ptrFromInt(base);
}

pub fn unmap(memory: []align(root.mem.PAGE_SIZE) u8) void {
    alloc_lock.lock();
    defer alloc_lock.unlock();

    const addr = @intFromPtr(memory.ptr);
    const region = find_region(addr) orelse @panic("allocator: invalid free");

    var i: usize = 0;
    while (i < region.pages) : (i += 1) {
        const vaddr = addr + i * root.mem.PAGE_SIZE;
        const phys = root.vmm.unmap_page(vaddr) orelse continue;

        root.vmm.frame_alloc.free(
            root.mem.PhysFrame.from(phys),
            0,
        );
    }

    remove_region(region);
    //free_region(region);
    root.vmm.flush_all();
}

fn realloc_internal(
    memory: []u8,
    new_len: usize,
    may_move: bool,
) ?[*]u8 {
    const page_size = root.mem.PAGE_SIZE;
    const addr = @intFromPtr(memory.ptr);

    const region = find_region(addr) orelse @panic("allocator: realloc unknown region");

    const old_pages = region.pages;
    const new_pages =
        root.mem.alignUp(new_len, page_size) / page_size;

    if (new_pages == old_pages)
        return memory.ptr;

    if (new_pages < old_pages) {
        var i = new_pages;
        while (i < old_pages) : (i += 1) {
            const vaddr = addr + i * page_size;
            const phys = root.vmm.unmap_page(vaddr) orelse continue;
            root.vmm.frame_alloc.free(
                root.mem.PhysFrame.from(phys),
                0,
            );
        }

        region.pages = new_pages;
        root.vmm.flush_all();
        return memory.ptr;
    }

    if (!may_move)
        return null;

    const new_ptr = map(new_len, .of(u8)) orelse return null;

    @memcpy(
        @as([*]u8, @ptrCast(new_ptr))[0..memory.len],
        memory,
    );

    unmap(@alignCast(memory));
    return new_ptr;
}

fn alloc(
    context: *anyopaque,
    n: usize,
    alignment: std.mem.Alignment,
    ra: usize,
) ?[*]u8 {
    _ = context;
    _ = ra;
    std.debug.assert(n > 0);
    return map(n, alignment);
}

fn resize(
    context: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    return_address: usize,
) bool {
    _ = context;
    _ = alignment;
    _ = return_address;

    alloc_lock.lock();
    defer alloc_lock.unlock();

    return realloc_internal(memory, new_len, false) != null;
}

fn remap(
    context: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    _ = context;
    _ = alignment;
    _ = return_address;

    alloc_lock.lock();
    defer alloc_lock.unlock();

    return realloc_internal(memory, new_len, true);
}

fn free(
    context: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    return_address: usize,
) void {
    _ = context;
    _ = alignment;
    _ = return_address;

    unmap(@alignCast(memory));
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
