const std = @import("std");

pub const Spinlock = struct {
    locked: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn lock(self: *@This()) void {
        while (true) : (std.atomic.spinLoopHint()) {
            if (self.locked.cmpxchgWeak(0, 1, .acquire, .monotonic) == null) break;
        }
    }

    pub fn unlock(self: *@This()) void {
        self.locked.store(0, .release);
    }
};
