pub const limine = @cImport({
    @cInclude("limine.h");
});

pub const MEMMAP_USABLE = 0;
pub const MEMMAP_RESERVED = 1;
pub const MEMMAP_ACPI_RECLAIMABLE = 2;
pub const MEMMAP_ACPI_NVS = 3;
pub const MEMMAP_BAD_MEMORY = 4;
pub const MEMMAP_BOOTLOADER_RECLAIMABLE = 5;
pub const MEMMAP_EXECUTABLE_AND_MODULES = 6;
pub const MEMMAP_FRAMEBUFFER = 7;

pub const memmap_request = limine.limine_memmap_request;
pub const memmap_response = limine.limine_memmap_response;
pub const memmap_entry = limine.limine_memmap_entry;

pub const framebuffer_request = limine.limine_framebuffer_request;
pub const framebuffer_response = limine.limine_framebuffer_response;
pub const framebuffer = limine.limine_framebuffer;

pub const hhdm_request = limine.limine_hhdm_request;
pub const hhdm_response = limine.limine_hhdm_response;
