const root = @import("klib");

pub const PAGE_SIZE = 4096;

pub const PageFlags = packed struct(u8) {
    free: bool = false,
    reserved: bool = false,
    _: u6 = 0,
};

pub const Page = struct {
    prev: ?*Page = null,
    next: ?*Page = null,

    flags: PageFlags = .{},
};
