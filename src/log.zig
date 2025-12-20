const root = @import("root").klib;
const uart = root.bdriver.uart.UARTDriver;

pub const LogLevel = enum {
    Info,
    Warn,
    Error,
    Fatal,
    Debug,
};

pub fn log(level: LogLevel, comptime msg: []const u8, args: anytype) void {
    const prefix: []const u8 = switch (level) {
        .Info => "[INFO]",
        .Warn => "[WARN]",
        .Error => "[ERROR]",
        .Fatal => "[FATAL]",
        .Debug => "[DEBUG]",
    };

    const _writer = uart.writer();
    var writer = @constCast(&_writer.interface);

    writer.print("{s} {s}\n", .{ prefix, msg } ++ args) catch unreachable;
}
