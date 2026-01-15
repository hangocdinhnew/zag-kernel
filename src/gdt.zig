const std = @import("std");

const Tss = extern struct {
    _reserved0: u32 = 0,

    rsp0: u64 = 0,
    rsp1: u64 = 0,
    rsp2: u64 = 0,

    _reserved1: u64 = 0,

    ist1: u64 = 0,
    ist2: u64 = 0,
    ist3: u64 = 0,
    ist4: u64 = 0,
    ist5: u64 = 0,
    ist6: u64 = 0,
    ist7: u64 = 0,

    _reserved2: u64 = 0,
    _reserved3: u16 = 0,

    iomap_base: u16 = @sizeOf(Tss),
};

const SystemSegmentType = enum(u4) {
    tss_available = 0b1001,
    tss_busy = 0b1011,
};

const SystemAccess = packed struct(u8) {
    stype: SystemSegmentType,
    zero: u1 = 0,
    dpl: u2 = 0,
    present: bool = true,
};

const Access = packed struct(u8) {
    accessed: bool = false,
    rw: bool = false,
    dc: bool = false,
    executable: bool = false,
    descriptor_type: bool = false,
    dpl: u2 = 0,
    present: bool = false,
};

const Descriptor = packed struct(u64) {
    limit_low: u16 = 0,
    base_low: u16 = 0,
    base_mid: u8 = 0,
    access: Access,
    flags_limit: u8,
    base_high: u8 = 0,
};

const TssDescriptorLow = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: SystemAccess,
    flags_limit: u8,
    base_high: u8,
};

const TssDescriptor = packed struct(u128) {
    low: TssDescriptorLow,
    base_upper: u32,
    reserved: u32 = 0,
};

const STACK_SIZE = 16 * 1024;

export var kernel_stack: [STACK_SIZE]u8 align(16) = undefined;
export var int_stack: [STACK_SIZE]u8 align(16) = undefined;

fn stackTop(stack: []u8) u64 {
    return (@intFromPtr(stack.ptr) + stack.len) & ~@as(u64, 0xF);
}

var tss: Tss = undefined;
fn initTss() void {
    tss = .{
        ._reserved0 = 0,
        .rsp0 = stackTop(&kernel_stack),
        .rsp1 = 0,
        .rsp2 = 0,
        ._reserved1 = 0,

        .ist1 = stackTop(&int_stack),
        .ist2 = 0,
        .ist3 = 0,
        .ist4 = 0,
        .ist5 = 0,
        .ist6 = 0,
        .ist7 = 0,

        ._reserved2 = 0,
        ._reserved3 = 0,
        .iomap_base = @sizeOf(Tss),
    };
}

fn makeTssDescriptor(tss_ptr: *const Tss) TssDescriptor {
    const base = @intFromPtr(tss_ptr);
    const limit = @sizeOf(Tss) - 1;

    return .{
        .low = .{
            .limit_low = @intCast(limit & 0xFFFF),
            .base_low = @intCast(base & 0xFFFF),
            .base_mid = @intCast((base >> 16) & 0xFF),
            .access = .{
                .stype = .tss_available,
                .dpl = 0,
                .present = true,
            },
            .flags_limit = @intCast((limit >> 16) & 0x0F),
            .base_high = @intCast((base >> 24) & 0xFF),
        },
        .base_upper = @intCast((base >> 32) & 0xFFFFFFFF),
    };
}

const FLAG_LONG_MODE = 1 << 5;

fn makeDescriptor(access: Access, flags: u8) Descriptor {
    return .{
        .access = access,
        .flags_limit = flags,
    };
}

const KERNEL_CODE_ACCESS: Access = .{
    .rw = true,
    .executable = true,
    .descriptor_type = true,
    .present = true,
};

const KERNEL_DATA_ACCESS: Access = .{
    .rw = true,
    .descriptor_type = true,
    .present = true,
};

var gdt = packed struct {
    none: Descriptor,
    code: Descriptor,
    data: Descriptor,
    tss: TssDescriptor,
}{
    .none = makeDescriptor(.{}, 0),
    .code = makeDescriptor(KERNEL_CODE_ACCESS, FLAG_LONG_MODE),
    .data = makeDescriptor(KERNEL_DATA_ACCESS, 0),
    .tss = undefined,
};

const GDTR = packed struct {
    limit: u16,
    base: usize,
};

pub noinline fn init() void {
    initTss();
    gdt.tss = makeTssDescriptor(&tss);

    const gdtr: GDTR = .{
        .limit = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intFromPtr(&gdt),
    };

    asm volatile (
        \\ lgdt (%rax)
        \\ call reloadSegments
        \\ mov $0x18, %ax
        \\ ltr %ax
        :
        : [ptr] "{rax}" (&gdtr),
        : .{ .memory = true });

    int_stack[0] = 1;
}

export fn reloadSegments() callconv(.naked) void {
    asm volatile (
        \\ pushq $0x08
        \\ leaq 1f(%rip), %rax
        \\ push %rax
        \\ lretq
        \\ 1:
        \\ mov $0x10, %ax
        \\ mov %ax, %ds
        \\ mov %ax, %es
        \\ mov %ax, %ss
        \\ ret
    );
}
