const std = @import("std");
pub const vec = @import("vec");
pub const map = @import("map");

pub fn set_alloc(alloc: std.mem.Allocator) void {
    vec.set_alloc(alloc);
    map.set_alloc(alloc);
}
