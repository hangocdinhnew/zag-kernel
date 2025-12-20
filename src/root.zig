pub const utils = @import("utils.zig");
pub const framebuffer = @import("framebuffer.zig");
pub const mem = @import("mem.zig");
pub const bdriver = @import("bdriver.zig");
pub const log = @import("log.zig");

pub inline fn check_base_rev(base_rev: [3]u64) void {
    if (base_rev[2] != 0)
        utils.hcf();
}

pub inline fn enable_sse() void {
    asm volatile (
        \\// Enable SSE and SSE2 support
        \\// CR0: clear EM (bit 2), set MP (bit 1)
        \\mov    %cr0, %rax
        \\and $0xFFFFFFFFFFFBFFFF, %rax    // clear EM
        \\or     $0x00020000, %rax    // set MP
        \\mov    %rax, %cr0
        \\// CR4: enable OSFXSR (bit 9) and OSXMMEXCPT (bit 10)
        \\mov    %cr4, %rax
        \\or     $0x600, %rax         // set bits 9 and 10
        \\mov    %rax, %cr4
        \\// Zero XMM registers
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
