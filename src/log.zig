const root = @import("root").klib;

pub const LogLevel = enum {
    Info,
    Warn,
    Error,
    Fatal,
    Debug,
};

pub const Logger = struct {
    bdriver: root.bdriver.BDriver,
    uart: root.bdriver.uart.UARTDriver,

    pub fn init(bdriver: ?root.bdriver.BDriver) @This() {
        var logger: @This() = undefined;

        const bdriver_extracted = bdriver.?;

        logger.bdriver = bdriver_extracted;
        logger.uart = logger.bdriver.uart;

        return logger;
    }

    pub fn log(self: @This(), level: LogLevel, msg: []const u8) void {
        const prefix: []const u8 = switch (level) {
            .Info => "[INFO] ",
            .Warn => "[WARN] ",
            .Error => "[ERROR] ",
            .Fatal => "[FATAL] ",
            .Debug => "[DEBUG] ",
        };

        self.uart.print(prefix);
        self.uart.print(msg);
    }
};
