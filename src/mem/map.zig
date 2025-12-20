const root = @import("root").klib;
const limine = @import("limine");

const log = root.log;

pub const Memmap = struct {
    response: *volatile limine.memmap_response,
    entry_usable: *volatile limine.memmap_entry,
    entry_kernelspace: *volatile limine.memmap_entry,

    pub fn init(request: limine.memmap_request) @This() {
        var memmap: @This() = undefined;

        if (request.response == null) {
            log.log(.Fatal, "Failed to get memmap response!\n", .{});
            unreachable;
        }

        memmap.response = @ptrCast(request.response);

        var has_usable = false;
        var has_kernelspace = false;

        for (0..memmap.response.entry_count) |i| {
            const zig_entry: *volatile limine.memmap_entry = @ptrCast(memmap.response.entries[i]);

            if (zig_entry.type == limine.MEMMAP_USABLE) {
                memmap.entry_usable = zig_entry;
                has_usable = true;
            }

            if (zig_entry.type == limine.MEMMAP_EXECUTABLE_AND_MODULES) {
                memmap.entry_kernelspace = zig_entry;
                has_kernelspace = true;
            }
        }

        if (!has_usable or !has_kernelspace) {
            log.log(.Fatal, "Failed to get usable or kernel space memory address!\n", .{});
            unreachable;
        }

        if (memmap.entry_usable.base == 0 or memmap.entry_usable.length == 0) {
            log.log(.Fatal, "Unusable entry_usable!\n", .{});
            unreachable;
        }

        if (memmap.entry_kernelspace.base == 0 or memmap.entry_kernelspace.length == 0) {
            log.log(.Fatal, "Unusable entry_kernelspace!\n", .{});
            unreachable;
        }

        for (0..memmap.response.entry_count) |i| {
            const zig_entry: *volatile limine.memmap_entry = @ptrCast(memmap.response.entries[i]);

            if (zig_entry.type == limine.MEMMAP_ACPI_RECLAIMABLE) {
                if (zig_entry.base == 0 or zig_entry.length == 0)
                    break;

                if (memmap.entry_usable.base + memmap.entry_usable.length != zig_entry.base)
                    break;

                memmap.entry_usable.length += zig_entry.length;
                zig_entry.base = 0;
                zig_entry.length = 0;
            }
        }

        log.log(.Info, "Memory is mapped!\n", .{});

        return memmap;
    }
};
