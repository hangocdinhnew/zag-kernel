const std = @import("std");

pub const PMO: usize = 0xFFFF_8000_0000_0000;

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
    free_lists: [MAX_ORDER + 1]?*FreeBlock,

    pub fn init() @This() {
        return .{
            .free_lists = [_]?*FreeBlock{null} ** (MAX_ORDER + 1),
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
    }

    pub fn alloc(self: *@This(), order: usize) ?PhysFrame {
        var o = order;

        while (o <= MAX_ORDER and self.free_lists[o] == null) {
            o += 1;
        }

        if (o > MAX_ORDER) return null;

        const block = self.free_lists[o].?;
        self.free_lists[o] = block.next;

        const addr = @intFromPtr(block) - PMO;

        while (o > order) {
            o -= 1;
            const buddy_addr = addr + bytes(o);
            const buddy: *FreeBlock = @ptrFromInt(buddy_addr + PMO);

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
        std.debug.assert(order <= MAX_ORDER);
        std.debug.assert(addr.to() % bytes(order) == 0);

        var current_addr = addr.to();
        var current_order = order;

        while (current_order < MAX_ORDER) {
            const buddy_addr = buddyOf(current_addr, current_order);

            var prev: ?*FreeBlock = null;
            var node = self.free_lists[current_order];

            while (node) |blk| {
                const blk_phys = @intFromPtr(blk) - PMO;
                if (blk_phys == buddy_addr) {
                    if (prev) |p| {
                        p.next = blk.next;
                    } else {
                        self.free_lists[current_order] = blk.next;
                    }

                    current_addr = @min(current_addr, buddy_addr);
                    current_order += 1;
                    continue;
                }

                prev = node;
                node = blk.next;
            }

            break;
        }

        const block: *FreeBlock = @ptrFromInt(current_addr + PMO);
        block.next = self.free_lists[current_order];
        self.free_lists[current_order] = block;
    }
};

pub inline fn get_pml4() *PageTable {
    const cr3 = asm volatile (
        \\mov %cr3, %[ret]
        : [ret] "=r" (-> usize),
        :
        : .{ .memory = true });

    return @ptrFromInt(cr3 + PMO);
}

pub inline fn log_info_location(comptime fmt: []const u8, args: anytype) void {
    const src = @src();

    std.log.info("{s}:{}:{}: " ++ fmt, .{ src.file, src.line, src.column } ++ args);
}

pub inline fn alloc_page(root_table_entry: *PageTableEntry, allocator: *FrameAllocator) *PageTable {
    var table: *PageTable = undefined;

    if (!root_table_entry.present) {
        const new_frame = allocator.alloc(0) orelse @panic("OOPM while allocating page table!");
        table = @ptrFromInt(new_frame.to() + PMO);
        @memset(&table.*, .{});
        root_table_entry.frame = @intCast(new_frame.addr);
        root_table_entry.present = true;
        root_table_entry.rw = true;
    } else {
        table = @ptrFromInt((root_table_entry.frame << 12) + PMO);
    }

    return table;
}

pub fn kmap(addr: VirtualAddress, frame: PhysFrame, _: PageTableEntry, allocator: *FrameAllocator) void {
    var pml4 = get_pml4();

    const pml4e = &pml4[addr.pml4_index];
    var pdpt: *PageTable = alloc_page(pml4e, allocator);

    const pdpte = &pdpt[addr.pdpt_index];
    var pd: *PageTable = alloc_page(pdpte, allocator);

    const pde = &pd[addr.pd_index];
    var pt: *PageTable = alloc_page(pde, allocator);

    var pte = &pt[addr.pt_index];
    pte.frame = @intCast(frame.addr);
    pte.present = true;
    pte.rw = true;
    pte.user = false;
    pte.nx = false;

    asm volatile (
        \\invlpg (%rax)
        :
        : [addr] "{rax}" (addr.to()),
        : .{ .memory = true });
}
