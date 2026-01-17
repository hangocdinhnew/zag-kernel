pub export var PMO: usize = 0xFFFF_8000_0000_0000;

pub const KERNEL_HEAP_START: usize = 0xFFFF_C000_0000_0000;
pub const KERNEL_HEAP_END: usize = 0xFFFF_E000_0000_0000;

pub const std = @import("std");

pub const utils = @import("utils.zig");
pub const uart = @import("uart.zig");
pub const mem = @import("mem.zig");
pub const smp = @import("smp.zig");
pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const vmm = @import("vmm.zig");
pub const allocator = @import("allocator.zig");

pub const UARTSpeed = uart.Speed;
pub const kprint = uart.kprint;

pub inline fn check_base_rev(base_rev: [3]u64) void {
    if (base_rev[2] != 0)
        utils.hcf();
}

pub inline fn enable_sse() void {
    asm volatile (
        \\mov    %cr0, %rax
        \\and $0xFFFFFFFFFFFBFFFF, %rax
        \\or     $0x00020000, %rax
        \\mov    %rax, %cr0
        \\mov    %cr4, %rax
        \\or     $0x600, %rax
        \\mov    %rax, %cr4
        \\pxor   %xmm0, %xmm0
        \\pxor   %xmm1, %xmm1
        \\pxor   %xmm2, %xmm2
        \\pxor   %xmm3, %xmm3
        \\pxor   %xmm4, %xmm4
        \\pxor   %xmm5, %xmm5
        \\pxor   %xmm6, %xmm6
        \\pxor   %xmm7, %xmm7
        ::: .{ .memory = true });
}

pub inline fn enable_avx() void {
    asm volatile (
        \\mov %cr4, %eax
        \\or $0x200, %rax
        \\or $0x40000, %rax
        \\mov %rax, %cr4
        \\xor %%ecx, %%ecx
        \\mov $0x6, %%eax
        \\xor %%edx, %%edx
        \\xsetbv
        ::: .{ .rax = true, .rcx = true, .rdx = true });
}
