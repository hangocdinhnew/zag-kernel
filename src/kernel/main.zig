const klib = @import("klib");

export fn _start() noreturn {
    klib.utils.halt();
}
