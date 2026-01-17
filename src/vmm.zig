const root = @import("root").klib;
const std = @import("std");

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

pub const VmFlags = packed struct(u8) {
    rw: bool = true,
    user: bool = false,
    nx: bool = true,
    global: bool = true,
    _padding: u4 = 0,
};

pub const VmRegion = struct {
    start: usize,
    size: usize,
    flags: VmFlags,
    next: ?*VmRegion = null,
};

var kernel_pml4: *PageTable = undefined;
var frame_alloc: *root.mem.FrameAllocator = undefined;

var region_head: ?*VmRegion = null;

var vmm_lock = root.smp.Spinlock{};

inline fn physToVirt(phys: usize) usize {
    return phys + root.PMO;
}

inline fn virtToPhys(virt: usize) usize {
    return virt - root.PMO;
}

inline fn flush_tlb(addr: usize) void {
    asm volatile (
        \\invlpg (%rax)
        :
        : [addr] "{rax}" (addr),
        : .{ .memory = true });
}

inline fn flush_tlb_all() void {
    asm volatile (
        \\mov %cr3, %rax
        \\mov %rax, %cr3
        ::: .{ .memory = true });
}

noinline fn getPML4() *PageTable {
    var cr3: usize = undefined;
    asm volatile (
        \\mov %cr3, %[out]
        : [out] "=r" (cr3),
        :
        : .{ .memory = true });
    return @ptrFromInt(physToVirt(cr3));
}

fn findFreeRegion(size: usize) usize {
    var addr: usize = root.KERNEL_HEAP_START;

    var node = region_head;
    while (node) |r| {
        if (addr + size <= r.start) {
            return addr;
        }
        addr = r.start + r.size;
        node = r.next;
    }

    return addr;
}

pub fn findRegionByAddr(addr: usize) ?*VmRegion {
    var node = region_head;
    while (node) |r| {
        if (r.start == addr)
            return r;
        node = r.next;
    }
    return null;
}

fn insertRegion(region: *VmRegion) void {
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

fn allocTable(parent: *PageTableEntry) *PageTable {
    if (!parent.present) {
        const frame = frame_alloc.alloc(0) orelse @panic("OOM while allocating page table");

        const table: *PageTable = @ptrFromInt(physToVirt(frame.to()));
        @memset(table, .{});

        parent.frame = @intCast(frame.addr);
        parent.present = true;
        parent.rw = true;
        parent.user = false;
    }

    return @ptrFromInt(physToVirt(parent.frame << root.mem.PAGE_SHIFT));
}

// DOESN'T FLUSH TLB FOR YOU
fn mapPage(virt: usize, phys: usize, flags: PageTableEntry) void {
    const addr: root.mem.VirtualAddress = @bitCast(virt);

    const pml4 = kernel_pml4;
    const pdpt = allocTable(&pml4[addr.pml4_index]);
    const pd = allocTable(&pdpt[addr.pdpt_index]);
    const pt = allocTable(&pd[addr.pd_index]);

    var pte = &pt[addr.pt_index];
    pte.* = flags;
    pte.frame = @intCast(phys >> root.mem.PAGE_SHIFT);
    pte.present = true;
}

fn unmapPage(virt: usize) void {
    const addr: root.mem.VirtualAddress = @bitCast(virt);

    const pml4 = kernel_pml4;
    const pml4e = &pml4[addr.pml4_index];
    if (!pml4e.present) return;

    const pdpt: *PageTable = @ptrFromInt(physToVirt(pml4e.frame << root.mem.PAGE_SHIFT));
    const pdpte = &pdpt[addr.pdpt_index];
    if (!pdpte.present) return;

    const pd: *PageTable = @ptrFromInt(physToVirt(pdpte.frame << root.mem.PAGE_SHIFT));
    const pde = &pd[addr.pd_index];
    if (!pde.present) return;

    const pt: *PageTable = @ptrFromInt(physToVirt(pde.frame << root.mem.PAGE_SHIFT));
    const pte = &pt[addr.pt_index];
    if (!pte.present) return;

    const phys = pte.frame << root.mem.PAGE_SHIFT;
    pte.* = .{};

    frame_alloc.free(root.mem.PhysFrame.from(phys), 0);
}

pub fn init(allocator: *root.mem.FrameAllocator) void {
    frame_alloc = allocator;

    kernel_pml4 = getPML4();

    var phys: usize = frame_alloc.base;
    while (phys < frame_alloc.end) : (phys += root.mem.PAGE_SIZE) {
        mapPage(
            physToVirt(phys),
            phys,
            .{
                .rw = true,
                .global = true,
                .nx = true,
            },
        );
    }

    flush_tlb_all();
}

pub fn kalloc_pages(count: usize) ?*anyopaque {
    vmm_lock.lock();
    defer vmm_lock.unlock();

    const size = count * root.mem.PAGE_SIZE;
    const base = findFreeRegion(size);

    const region: *VmRegion = @ptrFromInt(physToVirt((frame_alloc.alloc(0) orelse {
        std.log.err("kalloc_pages: OOM", .{});
        return null;
    }).to()));

    region.* = .{
        .start = base,
        .size = size,
        .flags = .{},
        .next = null,
    };

    insertRegion(region);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const frame = frame_alloc.alloc(0) orelse {
            std.log.err("kalloc_pages: OOM", .{});
            return null;
        };
        const vaddr = base + i * root.mem.PAGE_SIZE;

        mapPage(
            vaddr,
            frame.to(),
            .{
                .rw = true,
                .global = true,
                .nx = true,
            },
        );

        @memset(@as(*[root.mem.PAGE_SIZE]u8, @ptrFromInt(vaddr)), 0);
        flush_tlb(vaddr);
    }

    return @ptrFromInt(base);
}

pub fn kfree_pages(ptr: *anyopaque) void {
    vmm_lock.lock();
    defer vmm_lock.unlock();

    const addr = @intFromPtr(ptr);

    var prev: ?*VmRegion = null;
    var cur = region_head;

    while (cur) |r| {
        if (r.start == addr) {
            const pages = r.size / root.mem.PAGE_SIZE;

            var i: usize = 0;
            while (i < pages) : (i += 1) {
                unmapPage(addr + i * root.mem.PAGE_SIZE);
                flush_tlb(addr + i * root.mem.PAGE_SIZE);
            }

            if (prev) |p| {
                p.next = r.next;
            } else {
                region_head = r.next;
            }

            return;
        }

        prev = cur;
        cur = r.next;
    }

    @panic("kfree_pages: invalid pointer");
}

pub fn realloc(
    uncasted_memory: []u8,
    new_len: usize,
    may_move: bool,
) ?[*]u8 {
    vmm_lock.lock();
    defer vmm_lock.unlock();

    const ptr = uncasted_memory.ptr;
    const addr = @intFromPtr(ptr);

    const region = findRegionByAddr(addr) orelse @panic("Failed to find region by address");

    const page_size = root.mem.PAGE_SIZE;

    const old_pages = region.size / page_size;
    const new_pages = root.mem.alignUp(new_len, page_size) / page_size;

    if (old_pages == new_pages)
        return ptr;

    if (new_pages < old_pages) {
        var i = new_pages;
        while (i < old_pages) : (i += 1) {
            const vaddr = addr + i * page_size;
            unmapPage(vaddr);
            flush_tlb(vaddr);
        }

        region.size = new_pages * page_size;
        return ptr;
    }

    if (!may_move)
        return null;

    const new_ptr = kalloc_pages(new_pages);

    @memcpy(
        @as([*]u8, @ptrCast(new_ptr))[0..uncasted_memory.len],
        uncasted_memory,
    );

    kfree_pages(ptr);
    return @ptrCast(new_ptr);
}
