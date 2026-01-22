const std = @import("std");
const root = @import("root").klib;

const smp = root.smp;

pub const FRAME_SIZE: usize = 4096;

pub const PhysFrame = packed struct(usize) {
    addr: usize,

    pub fn from(physaddr: usize) @This() {
        return .{
            .addr = physaddr >> PAGE_SHIFT,
        };
    }

    pub fn to(self: @This()) usize {
        return self.addr << PAGE_SHIFT;
    }
};

pub const VirtualAddress = packed struct(usize) {
    page_offset: u12,
    pt_index: u9,
    pd_index: u9,
    pdpt_index: u9,
    pml4_index: u9,
    sign_extension: u16,

    pub fn from(physaddr: usize) @This() {
        return @bitCast(physaddr);
    }

    pub fn to(self: @This()) usize {
        return @bitCast(self);
    }
};

pub const PAGE_SHIFT = 12;
pub const PAGE_SIZE = 1 << PAGE_SHIFT;
pub const MAX_ORDER = 10;

const FreeBlock = struct {
    next: ?*FreeBlock,
    order: u8,
};

inline fn pages(order: usize) usize {
    return @as(usize, 1) << @intCast(order);
}

inline fn bytes(order: usize) usize {
    return pages(order) * PAGE_SIZE;
}

inline fn buddyOf(addr: usize, order: usize) usize {
    return addr ^ bytes(order);
}

pub inline fn alignUp(x: usize, a: usize) usize {
    return (x + a - 1) & ~(a - 1);
}

pub inline fn alignDown(x: usize, a: usize) usize {
    return x & ~(a - 1);
}

inline fn largestOrderThatFits(addr: usize, end: usize) usize {
    var order: usize = MAX_ORDER;

    while (order > 0) {
        const size = bytes(order);
        if (addr % size == 0 and addr + size <= end) {
            return order;
        }
        order -= 1;
    }

    return 0;
}

pub const FrameAllocator = struct {
    spinlock: root.smp.Spinlock = .{},
    free_lists: [MAX_ORDER + 1]?*FreeBlock,
    offset: usize,

    total_pages: usize = 0,

    pub fn init(offset: usize) @This() {
        return .{
            .free_lists = [_]?*FreeBlock{null} ** (MAX_ORDER + 1),
            .offset = offset,
        };
    }

    pub fn add_region(self: *@This(), base: usize, length: usize) void {
        var start = alignUp(base, PAGE_SIZE);
        const end = alignDown(base + length, PAGE_SIZE);

        if (start >= end) return;

        const region_pages = (end - start) / PAGE_SIZE;

        while (start < end) {
            const order = largestOrderThatFits(start, end);

            self.freeInternal(PhysFrame.from(start), order);
            start += bytes(order);
        }

        self.total_pages += region_pages;
    }

    pub fn alloc(self: *@This(), order: usize) ?PhysFrame {
        const flags = self.spinlock.lock();
        defer self.spinlock.unlock(flags);

        var o = order;

        while (o <= MAX_ORDER and self.free_lists[o] == null) {
            o += 1;
        }

        if (o > MAX_ORDER) return null;

        const block = self.free_lists[o].?;
        self.free_lists[o] = block.next;

        std.debug.assert(block.order == o);
        block.order = 0xFF;

        const addr = @intFromPtr(block) - self.offset;

        while (o > order) {
            o -= 1;
            const buddy_addr = addr + bytes(o);
            const buddy: *FreeBlock = @ptrFromInt(buddy_addr + self.offset);

            buddy.next = self.free_lists[o];
            buddy.order = @intCast(o);
            self.free_lists[o] = buddy;
        }

        return PhysFrame.from(addr);
    }

    inline fn NOLOCK_freeInternal(self: *@This(), addr: PhysFrame, order: usize) void {
        var current_addr = addr.to();
        var current_order = order;

        merge: while (current_order < MAX_ORDER) {
            const buddy_addr = buddyOf(current_addr, current_order);

            var prev: ?*FreeBlock = null;
            var node = self.free_lists[current_order];

            while (node) |blk| {
                const blk_phys = @intFromPtr(blk) - self.offset;
                std.debug.assert(blk.order == current_order);

                if (blk_phys == buddy_addr) {
                    if (prev) |p| {
                        p.next = blk.next;
                    } else {
                        self.free_lists[current_order] = blk.next;
                    }

                    current_addr = @min(current_addr, buddy_addr);
                    current_order += 1;
                    continue :merge;
                }

                prev = node;
                node = blk.next;
            }

            break;
        }

        const block: *FreeBlock = @ptrFromInt(current_addr + self.offset);
        block.order = @intCast(current_order);
        block.next = self.free_lists[current_order];
        self.free_lists[current_order] = block;
    }

    fn freeInternal(self: *@This(), addr: PhysFrame, order: usize) void {
        const flags = self.spinlock.lock();
        defer self.spinlock.unlock(flags);

        NOLOCK_freeInternal(self, addr, order);
    }

    pub fn free(
        self: *@This(),
        addr: PhysFrame,
        order: usize,
    ) void {
        const flags = self.spinlock.lock();
        defer self.spinlock.unlock(flags);

        std.debug.assert(order <= MAX_ORDER);
        std.debug.assert(addr.to() % bytes(order) == 0);

        const block_ptr: *FreeBlock =
            @ptrFromInt(addr.to() + self.offset);

        std.debug.assert(block_ptr.order == 0xFF);

        NOLOCK_freeInternal(self, addr, order);
    }
};
