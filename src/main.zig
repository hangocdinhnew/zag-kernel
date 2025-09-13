pub const limine = @cImport({
    @cInclude("limine.h");
});

pub export var start_marker: [4]u64 linksection(".limine_requests_start") = [4]u64{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub export var end_marker: [2]u64 linksection(".limine_requests_end") = [2]u64{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };

pub export var base_revision: [3]u64 linksection(".limine_requests") = [3]u64{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3 };

const klib = @import("klib");

export fn _start() noreturn {
    klib.utils.halt();
}
