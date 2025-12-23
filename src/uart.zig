// Inspired by: https://raw.githubusercontent.com/os-chain/chain/refs/heads/master/kernel/src/uart.zig

const root = @import("root").klib;
const builtin = @import("builtin");
const std = @import("std");

const cpu = @import("arch/x86_64/cpu.zig");

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

pub const Speed = enum(usize) {
    pub const base = 115200;

    s115200 = 115200,
    s57600 = 57600,
    s38400 = 38400,
    s19200 = 19200,
    s9600 = 9600,
    s4800 = 4800,

    pub fn getBaudrate(self: Speed) usize {
        return @intFromEnum(self);
    }

    pub fn fromBaudrate(baudrate: usize) ?Speed {
        inline for (comptime std.enums.values(Speed)) |speed| {
            if (baudrate == speed.getBaudrate()) {
                return speed;
            }
        }
        return null;
    }

    pub fn getDivisor(self: Speed) u16 {
        return @intCast(@divExact(base, self.getBaudrate()));
    }
};

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

    pub fn init(speed: Speed) void {
        const port: u16 = @truncate(@intFromPtr(@This().base));

        cpu.outb(port + 3, 0x80);
        cpu.outb(port, @intCast(speed.getDivisor() >> 8));
        cpu.outb(port, @truncate(speed.getDivisor()));
        cpu.outb(port + 3, 0x0);

        cpu.outb(port + 3, 0x03); // 8 bits, no parity, 1 stop bit, no break control

        cpu.outb(port + 2, 0xc7); // FIFO enabled, clear both FIFOs, 14 bytes

        cpu.outb(port + 4, 0x03); // RTS, DTS
    }

    pub fn putc(c: u8) void {
        const port: u16 = @truncate(@intFromPtr(@This().base));
        while ((cpu.inb(port + 5) & 0x20) == 0) {}
        cpu.outb(port, c);
    }

    pub fn writer() Writer {
        return .init();
    }
};
