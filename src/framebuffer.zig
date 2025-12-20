const root = @import("root").klib;
const limine = @import("limine");

const log = root.log;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 0xff,

    pub fn toU32(self: @This()) u32 {
        return (@as(u32, self.b)) | (@as(u32, self.g) << 8) | (@as(u32, self.r) << 16) | (@as(u32, self.a) << 24);
    }
};

pub const WHITE = Color{ .r = 255, .g = 255, .b = 255 };
pub const BLACK = Color{ .r = 0, .g = 0, .b = 0 };

pub const RED = Color{ .r = 255, .g = 0, .b = 0 };
pub const GREEN = Color{ .r = 0, .g = 255, .b = 0 };
pub const BLUE = Color{ .r = 0, .g = 0, .b = 255 };
pub const YELLOW = Color{ .r = 255, .g = 255, .b = 0 };

pub const Framebuffer = struct {
    response: *volatile limine.framebuffer_response,
    fb: *volatile limine.framebuffer,
    fb_ptr: [*]volatile u32,

    ppr: usize,

    pub fn init(request: limine.framebuffer_request) @This() {
        var framebuffer: @This() = undefined;

        if (request.response == null) {
            log.log(.Fatal, "Framebuffer Request is Null!\n", .{});
            root.utils.hcf();
        }

        framebuffer.response = @ptrCast(request.response);

        if (framebuffer.response.framebuffer_count < 1) {
            log.log(.Fatal, "No framebuffers found!\n", .{});
            root.utils.hcf();
        }

        framebuffer.fb = framebuffer.response.framebuffers[0];
        framebuffer.fb_ptr = @ptrCast(@alignCast(framebuffer.fb.address));

        framebuffer.ppr = framebuffer.fb.pitch / 4;

        log.log(.Info, "Framebuffer initialized!\n", .{});

        return framebuffer;
    }

    pub fn write(self: *@This(), comptime T: type, x: T, y: T, color: Color) void {
        const convx: usize = @intCast(x);
        const convy: usize = @intCast(y);

        if (convx >= self.fb.width or convy >= self.fb.height) return;

        self.fb_ptr[convy * self.ppr + convx] = color.toU32();
    }

    pub fn clear_background(self: *@This(), color: Color) void {
        for (0..self.fb.width) |x| {
            for (0..self.fb.height) |y| {
                self.write(usize, x, y, color);
            }
        }
    }
};
