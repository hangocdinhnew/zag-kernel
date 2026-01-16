const root = @import("root").klib;
const std = @import("std");

var kernel_pml4: *root.mem.PageTable = undefined;
var frame_alloc: *root.mem.FrameAllocator = undefined;

var heap_cursor: usize = root.KERNEL_HEAP_START;

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

noinline fn getPML4() *root.mem.PageTable {
    var cr3: usize = undefined;
    asm volatile (
        \\mov %cr3, %[out]
        : [out] "=r" (cr3),
        :
        : .{ .memory = true });
    return @ptrFromInt(physToVirt(cr3));
}

fn allocTable(parent: *root.mem.PageTableEntry) *root.mem.PageTable {
    if (!parent.present) {
        const frame = frame_alloc.alloc(0) orelse @panic("OOM while allocating page table");

        const table: *root.mem.PageTable = @ptrFromInt(physToVirt(frame.to()));
        @memset(table, .{});

        parent.frame = @intCast(frame.addr);
        parent.present = true;
        parent.rw = true;
        parent.user = false;
    }

    return @ptrFromInt(physToVirt(parent.frame << root.mem.PAGE_SHIFT));
}

// DOESN'T FLUSH TLB FOR YOU
fn mapPage(virt: usize, phys: usize, flags: root.mem.PageTableEntry) void {
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

pub fn init(allocator: *root.mem.FrameAllocator) void {
    frame_alloc = allocator;

    kernel_pml4 = getPML4();

    var phys: usize = 0;
    while (phys < frame_alloc.length) : (phys += root.mem.PAGE_SIZE) {
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

pub fn kalloc_pages(count: usize) *anyopaque {
    vmm_lock.lock();
    defer vmm_lock.unlock();

    const size = count * root.mem.PAGE_SIZE;
    const base = heap_cursor;
    heap_cursor += size;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const frame = frame_alloc.alloc(0) orelse @panic("OOM in kalloc_pages");

        mapPage(
            base + i * root.mem.PAGE_SIZE,
            frame.to(),
            .{
                .rw = true,
                .global = true,
                .nx = true,
            },
        );
        flush_tlb(base + i * root.mem.PAGE_SIZE);
    }

    if (count > 1) {
        flush_tlb(base);
    } else {
        flush_tlb_all();
    }

    const pointer: *root.mem.PageTable = @ptrFromInt(base);
    return pointer;
}
