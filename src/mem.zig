const limine = @import("limine");
const page = @import("mem/page.zig");
const PageInfo = page.PageInfo;

pub const MemSys = struct {
    const Self = @This();

    pageInfo: PageInfo = .{},

    pub fn init(self: *Self, response: *limine.limine_memmap_response) void {
        self.pageInfo.init(response);
    }
};
