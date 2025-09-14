const builtin = @import("builtin");

pub fn hcf() noreturn {
    while (true) {
        switch (builtin.cpu.arch) {
            .x86_64 => asm volatile ("hlt"),
            .aarch64, .riscv64 => asm volatile ("wfi"),
            else => unreachable,
        }
    }
}
