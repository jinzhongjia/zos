const std = @import("std");
const multiboot_v1 = @import("multiboot").v1;
const x86 = @import("cpu").x86;
const tty = @import("tty.zig");

const STACK_NUM = 1024 * 1024;

pub var stack: [STACK_NUM]usize = [_]usize{0} ** STACK_NUM; // Stack of free physical page.
pub var stack_index: usize = 0; // Index into the stack.

/// Boundaries of the frame stack.
// size of stack
pub var stack_size: usize = undefined;
pub var stack_end: usize = undefined;

////
// Return the amount of variable elements (in bytes).
//
pub fn available() usize {
    return stack_index * x86.constant.PAGE_SIZE;
}

////
// Request a free physical page and return its address.
//
pub fn allocate() usize {
    if (stack_index == 0)
        tty.panic("out of memory", .{});

    stack_index -= 1;
    return stack[stack_index];
}

////
// Free a previously allocated physical page.
//
// Arguments:
//     address: Address of the page to be freed.
//
pub fn free(address: usize) void {
    var addr = x86.constant.pageBase(address);
    stack[stack_index] = addr;

    stack_index += 1;
}

////
// Scan the memory map to index all available memory.
//
// Arguments:
//     info: Information structure from bootloader.
//
pub fn initialize(info: *const multiboot_v1.Info) void {
    tty.step("Indexing Physical Memory", .{});

    if (!multiboot_v1.check_flag(info.flags, 0)) {
        tty.panic("mem info not enable!", .{});
    }
    if (!multiboot_v1.check_flag(info.flags, 6)) {
        tty.panic("Mmap not enable!", .{});
    }

    // if (!multiboot_v1.check_flag(info.flags, 3)) {
    //     tty.panic("mods not enable!", .{});
    // }

    // Place the stack of free pages after the last Multiboot module.
    {
        var map: usize = info.mmap_addr;
        while (map < info.mmap_addr + info.mmap_length) {
            var entry = @intToPtr(*multiboot_v1.MMap_entry, map);

            // Calculate the start and end of this memory area.
            // Here we just Brute force truncation of addresses
            var start = @truncate(usize, entry.addr);
            var end = @truncate(usize, start + entry.len);

            // Flag all the pages in this memory area as free.
            if (entry.type == multiboot_v1.MEMORY_AVAILABLE) {
                while (start < end) : (start += x86.constant.PAGE_SIZE) {
                    // When the When the machine memory is greater than 4G, a panic error is given
                    if (stack_index == STACK_NUM - 1) {
                        tty.panic("Memory map is not enough!\nBecause you machine memory is larger than 4G!", .{});
                    }
                    free(start);
                }
            }

            // Go to the next entry in the memory map.
            map += entry.size + @sizeOf(@TypeOf(entry.size));
        }
        stack_size = stack_index + 1;
    }
    stack_end = @ptrToInt(&stack) + @sizeOf(usize) * STACK_NUM;

    tty.stepOK();

    // print some info for the memory
    tty.println("memory is {d}MB", .{available() / 1024 / 1024});
}
