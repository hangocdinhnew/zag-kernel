pub const utils = @import("utils.zig");
pub const framebuffer = @import("framebuffer.zig");
pub const mem = @import("mem.zig");
pub const bdriver = @import("bdriver.zig");

pub fn check_base_rev(base_rev: [3]u64) void {
    if (base_rev[2] != 0)
        utils.hcf();
}
