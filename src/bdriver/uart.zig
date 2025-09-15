const root = @import("root").klib;
const builtin = @import("builtin");

pub const UARTDriver = struct {
    base: *anyopaque,

    pub fn init() @This() {
        var uart: @This() = undefined;

        switch (builtin.cpu.arch) {
            .x86_64 => uart.base = @ptrFromInt(0x3F8), // Works across platforms
            .aarch64 => uart.base = @ptrFromInt(0x0900_0000), // TODO: Use ARM's DTC.
            .riscv64 => uart.base = @ptrFromInt(0x1000_0000), // TODO: Use RISCV's FDT
            else => unreachable,
        }

        return uart;
    }

    pub fn putchar(self: *UARTDriver, c: u8) void {
        switch (builtin.cpu.arch) {
            .x86_64 => {
                const port: u16 = @truncate(self.base);
                while ((inb(port + 5) & 0x20) == 0) {}
                outb(port, c);
            },

            .aarch64 => {
                const dr: *volatile u32 = @ptrCast(@alignCast(self.base));
                const fr: *volatile u32 = @ptrFromInt(@intFromPtr(self.base) + 0x18);
                while ((fr.* & (1 << 5)) != 0) {}
                dr.* = c;
            },

            .riscv64 => {
                const thr: *volatile u8 = @ptrCast(@alignCast(self.base));
                const lsr: *volatile u8 = @ptrFromInt(@intFromPtr(self.base) + 0x05);
                while ((lsr.* & 0x20) == 0) {}
                thr.* = c;
            },

            else => unreachable,
        }
    }

    pub fn print(self: *UARTDriver, str: []const u8) void {
        for (str) |c| self.putchar(c);
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
