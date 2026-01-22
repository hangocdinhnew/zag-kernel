const std = @import("std");
const root = @import("root").klib;

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

var kernel_pml4: *PageTable = undefined;
pub var frame_alloc: *root.mem.FrameAllocator = undefined;

var vmm_lock: root.smp.Spinlock = .{};

pub inline fn physToVirt(phys: usize) usize {
    return phys + root.PMO;
}

pub inline fn virtToPhys(virt: usize) usize {
    return virt - root.PMO;
}

pub inline fn flush_local_page(virt: usize) void {
    asm volatile (
        \\invlpg (%rax)
        :
        : [addr] "{rax}" (virt),
        : .{ .memory = true });
}

pub inline fn flush_local_all() void {
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

fn allocTable(parent: *PageTableEntry) *PageTable {
    if (!parent.present) {
        const frame = frame_alloc.alloc(0) orelse @panic("vmm: OOM allocating page table");

        const table: *PageTable =
            @ptrFromInt(physToVirt(frame.to()));

        @memset(table, .{});

        parent.frame = @intCast(frame.addr);
        parent.present = true;
        parent.rw = true;
        parent.user = false;
    }

    return @ptrFromInt(
        physToVirt(parent.frame << root.mem.PAGE_SHIFT),
    );
}

pub fn map_page(
    virt: usize,
    phys: usize,
    flags: VmFlags,
) void {
    const va: root.mem.VirtualAddress = .from(virt);

    const pml4 = kernel_pml4;
    const pdpt = allocTable(&pml4[va.pml4_index]);
    const pd = allocTable(&pdpt[va.pdpt_index]);
    const pt = allocTable(&pd[va.pd_index]);

    var pte = &pt[va.pt_index];
    pte.* = .{};
    pte.present = true;
    pte.rw = flags.rw;
    pte.user = flags.user;
    pte.nx = flags.nx;
    pte.global = flags.global;
    pte.frame = @intCast(phys >> root.mem.PAGE_SHIFT);
}

pub fn unmap_page(virt: usize) ?usize {
    const flags = vmm_lock.lock();
    defer vmm_lock.unlock(flags);

    const va: root.mem.VirtualAddress = .from(virt);

    const pml4e = &kernel_pml4[va.pml4_index];
    if (!pml4e.present) return null;

    const pdpt: *PageTable =
        @ptrFromInt(physToVirt(pml4e.frame << root.mem.PAGE_SHIFT));
    const pdpte = &pdpt[va.pdpt_index];
    if (!pdpte.present) return null;

    const pd: *PageTable =
        @ptrFromInt(physToVirt(pdpte.frame << root.mem.PAGE_SHIFT));
    const pde = &pd[va.pd_index];
    if (!pde.present) return null;

    const pt: *PageTable =
        @ptrFromInt(physToVirt(pde.frame << root.mem.PAGE_SHIFT));
    const pte = &pt[va.pt_index];
    if (!pte.present) return null;

    const phys =
        pte.frame << root.mem.PAGE_SHIFT;

    pte.* = .{};
    return phys;
}

pub fn map_range(
    virt: usize,
    phys: usize,
    pages: usize,
    flags: VmFlags,
) void {
    var i: usize = 0;
    while (i < pages) : (i += 1) {
        map_page(
            virt + i * root.mem.PAGE_SIZE,
            phys + i * root.mem.PAGE_SIZE,
            flags,
        );
    }
}

pub fn unmap_range(
    virt: usize,
    pages: usize,
) void {
    var i: usize = 0;
    while (i < pages) : (i += 1) {
        _ = unmap_page(
            virt + i * root.mem.PAGE_SIZE,
        );
    }
}

pub fn protect_page(
    virt: usize,
    flags: VmFlags,
) void {
    vmm_lock.lock();
    defer vmm_lock.unlock();

    const va: root.mem.VirtualAddress = @bitCast(virt);

    const pml4e = &kernel_pml4[va.pml4_index];
    if (!pml4e.present) return;

    const pdpt: *PageTable =
        @ptrFromInt(physToVirt(pml4e.frame << root.mem.PAGE_SHIFT));
    const pdpte = &pdpt[va.pdpt_index];
    if (!pdpte.present) return;

    const pd: *PageTable =
        @ptrFromInt(physToVirt(pdpte.frame << root.mem.PAGE_SHIFT));
    const pde = &pd[va.pd_index];
    if (!pde.present) return;

    const pt: *PageTable =
        @ptrFromInt(physToVirt(pde.frame << root.mem.PAGE_SHIFT));
    const pte = &pt[va.pt_index];
    if (!pte.present) return;

    pte.rw = flags.rw;
    pte.user = flags.user;
    pte.nx = flags.nx;
    pte.global = flags.global;
}

pub fn init(
    allocator: *root.mem.FrameAllocator,
) void {
    frame_alloc = allocator;
    kernel_pml4 = getPML4();

    flush_local_all();
}
