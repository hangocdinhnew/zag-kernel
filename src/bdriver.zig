const root = @import("root").klib;
pub const uart = @import("bdriver/uart.zig");

pub const BDriver = struct {
    pub fn stage1init() void {
        uart.UARTDriver.init();
    }
};
