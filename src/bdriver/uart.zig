const root = @import("root").klib;
const builtin = @import("builtin");
const std = @import("std");

pub const UARTDriver = struct {
    pub var base: *anyopaque = undefined;

    pub const Writer = struct {
        interface: std.Io.Writer,

        pub fn init() Writer {
            return .{ .interface = .{
                .vtable = &.{
                    .drain = drain,
                },
                .buffer = &.{},
            } };
        }

        fn drain(
            io_w: *std.io.Writer,
            data: []const []const u8,
            splat: usize,
        ) std.io.Writer.Error!usize {
            _ = io_w;

            var written: usize = 0;

            for (data[0 .. data.len - 1]) |slice| {
                for (slice) |b| {
                    putc(b);
                    written += 1;
                }
            }

            if (splat != 0) {
                const pattern = data[data.len - 1];
                for (0..splat) |_| {
                    for (pattern) |b| {
                        UARTDriver.putc(b);
                        written += 1;
                    }
                }
            }

            return written;
        }
    };

    pub fn init() void {
        switch (builtin.cpu.arch) {
            .x86_64 => @This().base = @ptrFromInt(0x3F8), // Works across platforms
            .aarch64 => @This().base = @ptrFromInt(0x0900_0000), // TODO: Use ARM's DTC.
            .riscv64 => @This().base = @ptrFromInt(0x1000_0000), // TODO: Use RISCV's FDT
            else => unreachable,
        }
    }

    pub fn putc(c: u8) void {
        switch (builtin.cpu.arch) {
            .x86_64 => {
                const port: u16 = @truncate(@intFromPtr(@This().base));
                while ((inb(port + 5) & 0x20) == 0) {}
                outb(port, c);
            },

            .aarch64 => {
                const dr: *volatile u32 = @ptrCast(@alignCast(@This().base));
                const fr: *volatile u32 = @ptrFromInt(@intFromPtr(@This().base) + 0x18);
                while ((fr.* & (1 << 5)) != 0) {}
                dr.* = c;
            },

            .riscv64 => {
                const thr: *volatile u8 = @ptrCast(@alignCast(@This().base));
                const lsr: *volatile u8 = @ptrFromInt(@intFromPtr(@This().base) + 0x05);
                while ((lsr.* & 0x20) == 0) {}
                thr.* = c;
            },

            else => unreachable,
        }
    }

    pub fn clear() void {
        const esc = "\x1b[2J\x1b[H";
        @This().print(esc);
    }

    pub fn writer() Writer {
        return .init();
    }
};

fn outb(port: u16, value: u8) void {
    asm volatile ("outb %al, %dx"
        :
        : [val] "{al}" (value),
          [port] "{dx}" (port),
        : .{});
}

fn inb(port: u16) u8 {
    var ret: u8 = 0;
    asm volatile ("inb %dx, %al"
        : [ret] "={al}" (ret),
        : [port] "{dx}" (port),
        : .{});
    return ret;
}
