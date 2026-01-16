const std = @import("std");
const root = @import("root").klib;

const smp = root.smp;

pub const PageTable = [512]PageTableEntry;
pub const PageTableEntry = packed struct(usize) {
    present: bool = false,
    rw: bool = false,
    user: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    pat: bool = false,
    global: bool = false,
    available: u3 = 0,
    frame: u40 = 0,
    reserved: u11 = 0,
    nx: bool = false,
};

pub const FRAME_SIZE: usize = 4096;

pub const PhysFrame = packed struct(usize) {
    addr: usize,

    pub fn from(physaddr: usize) @This() {
        return .{
            .addr = physaddr >> 12,
        };
    }

    pub fn to(self: @This()) usize {
        return self.addr << 12;
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

inline fn alignUp(x: usize, a: usize) usize {
    return (x + a - 1) & ~(a - 1);
}

inline fn alignDown(x: usize, a: usize) usize {
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
    length: usize = 0,

    pub fn init(offset: usize) @This() {
        return .{
            .free_lists = [_]?*FreeBlock{null} ** (MAX_ORDER + 1),
            .offset = offset,
        };
    }

    pub fn setbootinfo(self: *@This(), base: usize, length: usize) void {
        var start = alignUp(base, PAGE_SIZE);
        const end = alignDown(base + length, PAGE_SIZE);

        while (start < end) {
            const order = largestOrderThatFits(start, end);
            self.free(PhysFrame.from(start), order);
            start += bytes(order);
        }

        self.length = alignDown(base + length, PAGE_SIZE);
    }

    pub fn alloc(self: *@This(), order: usize) ?PhysFrame {
        self.spinlock.lock();
        defer self.spinlock.unlock();

        var o = order;

        while (o <= MAX_ORDER and self.free_lists[o] == null) {
            o += 1;
        }

        if (o > MAX_ORDER) return null;

        const block = self.free_lists[o].?;
        self.free_lists[o] = block.next;

        const addr = @intFromPtr(block) - self.offset;

        while (o > order) {
            o -= 1;
            const buddy_addr = addr + bytes(o);
            const buddy: *FreeBlock = @ptrFromInt(buddy_addr + self.offset);

            buddy.next = self.free_lists[o];
            self.free_lists[o] = buddy;
        }

        return PhysFrame.from(addr);
    }

    pub fn free(
        self: *@This(),
        addr: PhysFrame,
        order: usize,
    ) void {
        self.spinlock.lock();
        defer self.spinlock.unlock();

        std.debug.assert(order <= MAX_ORDER);
        std.debug.assert(addr.to() % bytes(order) == 0);

        var current_addr = addr.to();
        var current_order = order;

        while (current_order < MAX_ORDER) {
            const buddy_addr = buddyOf(current_addr, current_order);

            var prev: ?*FreeBlock = null;
            var node = self.free_lists[current_order];

            blk: while (node) |blk| {
                const blk_phys = @intFromPtr(blk) - self.offset;
                if (blk_phys == buddy_addr) {
                    if (prev) |p| {
                        p.next = blk.next;
                    } else {
                        self.free_lists[current_order] = blk.next;
                    }

                    current_addr = @min(current_addr, buddy_addr);
                    current_order += 1;
                    continue :blk;
                }

                prev = node;
                node = blk.next;
            }

            break;
        }

        const block: *FreeBlock = @ptrFromInt(current_addr + self.offset);
        block.next = self.free_lists[current_order];
        self.free_lists[current_order] = block;
    }
};
