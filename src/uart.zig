const root = @import("root").klib;
const builtin = @import("builtin");
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

var uart_mutex: Spinlock = .{};
var uart__writer = UART.writer();
var uart_writer = &uart__writer.interface;

fn lockUartWriter() *std.Io.Writer {
    uart_mutex.lock();
    return uart_writer;
}

fn unlockUartWriter() void {
    uart_writer.end = 0;
    uart_mutex.unlock();
}

pub inline fn kprint(comptime fmt: []const u8, args: anytype) void {
    const bw = lockUartWriter();
    defer unlockUartWriter();

    nosuspend bw.print(fmt, args) catch return;
}

pub const UART = struct {
    pub const base: *anyopaque = @ptrFromInt(0x3F8);

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
                        UART.putc(b);
                        written += 1;
                    }
                }
            }

            return written;
        }
    };

    pub fn putc(c: u8) void {
        const port: u16 = @truncate(@intFromPtr(@This().base));
        while ((inb(port + 5) & 0x20) == 0) {}
        outb(port, c);
    }

    pub fn writer() Writer {
        return .init();
    }
};

inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %al, %dx"
        :
        : [val] "{al}" (value),
          [port] "{dx}" (port),
        : .{});
}

inline fn inb(port: u16) u8 {
    var ret: u8 = 0;
    asm volatile ("inb %dx, %al"
        : [ret] "={al}" (ret),
        : [port] "{dx}" (port),
        : .{});
    return ret;
}
