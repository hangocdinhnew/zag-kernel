const std = @import("std");

inline fn irqDisable() usize {
    var flags: usize = undefined;
    asm volatile (
        \\pushfq
        \\pop %[flags]
        \\cli
        : [flags] "=r" (flags),
        :
        : .{ .memory = true });
    return flags;
}

inline fn irqRestore(flags: usize) void {
    asm volatile (
        \\push %[flags]
        \\popfq
        :
        : [flags] "r" (flags),
        : .{ .memory = true });
}

pub const Spinlock = struct {
    locked: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn lock(self: *@This()) usize {
        const flags = irqDisable();
        while (true) : (std.atomic.spinLoopHint()) {
            if (self.locked.cmpxchgStrong(0, 1, .acquire, .monotonic) == null) break;
        }
        return flags;
    }

    pub fn unlock(self: *@This(), flags: usize) void {
        self.locked.store(0, .release);
        irqRestore(flags);
    }
};
