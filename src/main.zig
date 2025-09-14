pub const klib = @import("klib");
const limine = @import("limine");

const LIMINE_MAGIC1 = 0xc7b1dd30df4c8b88;
const LIMINE_MAGIC2 = 0x0a82e883a194f07b;

pub export var start_marker: [4]u64 linksection(".limine_requests_start") = [4]u64{ 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9 };
pub export var end_marker: [2]u64 linksection(".limine_requests_end") = [2]u64{ 0xadc0e0531bb10d03, 0x9572709f31764c62 };
pub export var base_revision: [3]u64 linksection(".limine_requests") = [3]u64{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3 };

pub export var memmap_request: limine.memmap_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_MAGIC1, LIMINE_MAGIC2, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62 },
    .revision = 0,
};

pub export var framebuffer_request: limine.framebuffer_request linksection(".limine_requests") = .{
    .id = [4]u64{ LIMINE_MAGIC1, LIMINE_MAGIC2, 0x9d5827dcd881dd75, 0xa3148604f6fab11b },
    .revision = 0,
};

export fn _start() noreturn {
    klib.check_base_rev(base_revision);

    var fb = klib.framebuffer.Framebuffer.init(framebuffer_request);
    fb.check_nopanic(klib.framebuffer.RED);

    _ = klib.mem.Mem.init(memmap_request);
    fb.check_nopanic(klib.framebuffer.GREEN);

    const bdriver = klib.bdriver.BDriver.init();
    fb.check_nopanic(klib.framebuffer.BLUE);

    var uart = bdriver.uart;
    uart.print("Hello, World!");

    while (true) {}
}
