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

export var gdt = [_]Descriptor{
    makeDescriptor(.{}, 0),
    makeDescriptor(KERNEL_CODE_ACCESS, FLAG_LONG_MODE),
    makeDescriptor(KERNEL_DATA_ACCESS, 0),
};

const GDTR = packed struct {
    limit: u16,
    base: usize,
};

var gdtr: GDTR = .{
    .limit = @sizeOf(@TypeOf(gdt)) - 1,
    .base = 0,
};

pub fn load() void {
    gdtr.base = @intFromPtr(&gdt);

    asm volatile (
        \\ lgdt (%rax)
        \\ call reloadSegments
        :
        : [ptr] "{rax}" (&gdtr),
        : .{ .memory = true });
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
