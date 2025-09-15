const root = @import("root").klib;
pub const uart = @import("bdriver/uart.zig");

pub const BDriver = struct {
    uart: uart.UARTDriver,

    pub fn stage1init() @This() {
        var bdriver: @This() = undefined;

        bdriver.uart = uart.UARTDriver.init();

        return bdriver;
    }
};
