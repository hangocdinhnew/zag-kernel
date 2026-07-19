pub const klib = @import("klib");
pub const builtin = @import("builtin");
pub const std = @import("std");
const limine = @import("limine");

pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    klib.utils.hcf();
}

const LIMINE_COMMON_MAGIC1: usize = 0xc7b1dd30df4c8b88;
const LIMINE_COMMON_MAGIC2: usize = 0x0a82e883a194f07b;

pub export var start_marker: [4]u64 linksection(".limine_requests_start") = [4]u64{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub export var end_marker: [2]u64 linksection(".limine_requests_end") = [2]u64{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };
pub export var base_revision: [3]u64 linksection(".limine_requests") = [3]u64{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 4 };

pub export var hhdm_request: limine.limine_hhdm_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_COMMON_MAGIC1, LIMINE_COMMON_MAGIC2, 0x48dcf1cb8ad2b852, 0x63984e959a98244b },
    .revision = 0,
};

export fn _start() noreturn {
    klib.check_base_rev(base_revision);

    if (builtin.cpu.arch == .x86_64) {
        klib.enable_sse();
        if (builtin.cpu.has(.x86, .avx)) klib.enable_avx();
    }

    var hhdm_is_enabled = true;

    if (hhdm_request.response == null) {
        hhdm_is_enabled = false;
    }

    if (hhdm_is_enabled) {
        const response = hhdm_request.response;
        klib.hhdmBase = response.*.offset;
    }

    klib.utils.hcf();
}
