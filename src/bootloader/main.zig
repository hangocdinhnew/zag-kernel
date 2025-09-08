const std = @import("std");
const uefi = std.os.uefi;

pub fn main() void {
    ziggy_bootloader_main();
}

pub fn ziggy_bootloader_main() void {
    const con_out = uefi.system_table.con_out.?;
    _ = con_out.reset(true) catch unreachable;
    _ = con_out.clearScreen() catch unreachable;
    _ = con_out.outputString(std.unicode.utf8ToUtf16LeStringLiteral("Hello, World\r\n")) catch unreachable;
}
