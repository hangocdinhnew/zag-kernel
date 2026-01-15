const std = @import("std");

const Entry = packed struct(u128) {
    offset_low: u16,
    selector: u16,
    ist: u8,
    attributes: u8,
    offset_mid: u16,
    offset_high: u32,
    zero: u32 = 0,

    pub fn init(handler: usize, selector: u16, ist: u8, attributes: u8) @This() {
        return .{
            .offset_low = @intCast(handler & 0xFFFF),
            .selector = selector,
            .ist = ist & 0x7,
            .attributes = attributes,
            .offset_mid = @intCast((handler >> 16) & 0xFFFF),
            .offset_high = @intCast((handler >> 32) & 0xFFFFFFFF),
            .zero = 0,
        };
    }
};

const Register = packed struct {
    limit: u16,
    base: usize,
};

export var idt: [256]Entry = undefined;

const InterruptStackFrame = extern struct {
    rip: usize,
    cs: usize,
    rflags: usize,
    rsp: usize,
    ss: usize,
};

pub const IDT_ATTR_INTERRUPT_GATE: u8 = 0x8E;
inline fn setIDTEntry(vector: u8, handler: usize) void {
    idt[vector] = .init(
        handler,
        0x08,
        0,
        IDT_ATTR_INTERRUPT_GATE,
    );
}

// HANDLER

inline fn save_rsp() usize {
    var old_rsp: usize = 0;
    asm volatile (
        \\ mov %%rsp, %[out]
        \\ and $-16, %%rsp
        : [out] "=r" (old_rsp),
        :
        : .{ .memory = true });

    return old_rsp;
}

inline fn restore_rsp(old_rsp: usize) void {
    asm volatile (
        \\ mov %[in], %%rsp
        :
        : [in] "r" (old_rsp),
        : .{
          .memory = true,
        });
}

const PfError = packed struct(u64) {
    present: bool,
    write: bool,
    user: bool,
    reserved: bool,
    instr_fetch: bool,
    pkey: bool,
    shadow_stack: bool,
    _: u57 = 0,
};

fn pfHandler(
    frame: *InterruptStackFrame,
    error_code: PfError,
) callconv(.{ .x86_64_interrupt = .{} }) void {
    const old_rsp = save_rsp();

    std.debug.panic(
        \\ Page Fault!
        \\ Stack Frame: {any}
        \\ Error Code: {any}
    , .{ frame, error_code });

    restore_rsp(old_rsp);
}

fn gpHandler(
    isf: *InterruptStackFrame,
    error_code: usize,
) callconv(.{ .x86_64_interrupt = .{} }) void {
    const old_rsp = save_rsp();

    std.debug.panic(
        \\ GP Fault!
        \\ Stack Frame: {any}
        \\ Error code: {d}
    , .{ isf, error_code });

    restore_rsp(old_rsp);
}

fn dfHandler(
    _: *InterruptStackFrame,
    _: usize,
) callconv(.{ .x86_64_interrupt = .{} }) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

//////////

pub noinline fn init() void {
    for (&idt) |*entry| {
        entry.* = std.mem.zeroes(Entry);
    }

    const idtr: Register = .{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };

    setIDTEntry(14, @intFromPtr(&pfHandler));
    setIDTEntry(13, @intFromPtr(&gpHandler));
    setIDTEntry(8, @intFromPtr(&dfHandler));
    idt[8].ist = 1;

    asm volatile (
        \\ lidt (%rax)
        \\ sti
        :
        : [idtr] "{rax}" (&idtr),
        : .{ .memory = true });
}
