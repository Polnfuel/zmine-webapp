const std = @import("std");
const vec = @import("vec");

var allocator: std.mem.Allocator = undefined;

pub fn set_alloc(alloc: std.mem.Allocator) void {
    allocator = alloc;
}

pub const miniset16 = struct {
    data: [24]u16,
    size: u8,

    pub fn has(self: *miniset16, value: u16) bool {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            if (self.data[i] == value) {
                return true;
            }
        }
        return false;
    }

    pub fn at(self: *const miniset16, index: usize) u16 {
        return self.data[index];
    }

    pub fn ins(self: *miniset16, value: u16) void {
        if (!self.has(value)) {
            self.data[self.size] = value;
            self.size += 1;
        }
    }
};

pub const mapvec64 = struct {
    array: []?vec.vec64,

    pub fn new(size: usize) !mapvec64 {
        const arr = try allocator.alloc(?vec.vec64, size);

        @memset(arr, null);
        return mapvec64{ .array = arr };
    }

    pub fn has(self: mapvec64, key: usize) bool {
        if (self.array[key] == null) {
            return false;
        }
        return true;
    }

    pub fn empty(self: mapvec64) bool {
        var i: usize = 0;
        while (i < self.array.len) : (i += 1) {
            if (self.array[i] != null) {
                return false;
            }
        }
        return true;
    }

    pub fn at(self: mapvec64, key: usize) ?vec.vec64 {
        return self.array[key];
    }

    pub fn set(self: mapvec64, key: usize, value: vec.vec64) void {
        self.array[key] = value;
    }

    pub fn first(self: mapvec64) u8 {
        var i: usize = 0;
        while (i < self.array.len) : (i += 1) {
            if (self.array[i] != null) {
                return @truncate(i);
            }
        }
        unreachable;
    }

    pub fn free(self: *mapvec64) void {
        var i: usize = 0;
        while (i < self.array.len) : (i += 1) {
            const p = self.array[i];
            if (p != null) {
                const pp = p.?;
                allocator.free(pp.array);
            }
        }
        allocator.free(self.array);
    }
};

pub const mapvecf64 = struct {
    array: []f64,

    pub fn new(size: usize) !mapvecf64 {
        const arr = try allocator.alloc(f64, size);
        return mapvecf64{ .array = arr };
    }

    pub fn at(self: mapvecf64, key: usize) f64 {
        return self.array[key];
    }

    pub fn set(self: mapvecf64, key: usize, value: f64) void {
        self.array[key] = value;
    }

    pub fn free(self: *mapvecf64) void {
        allocator.free(self.array);
    }
};

pub const vecmapvec64 = struct {
    array: []mapvec64,

    pub fn new(size: usize) !vecmapvec64 {
        const arr = try allocator.alloc(mapvec64, size);
        return vecmapvec64{ .array = arr };
    }

    pub fn at(self: vecmapvec64, index: usize) mapvec64 {
        return self.array[index];
    }

    pub fn set(self: *vecmapvec64, index: usize, value: mapvec64) void {
        self.array[index] = value;
    }

    pub fn free(self: *vecmapvec64) void {
        var i: usize = 0;
        while (i < self.array.len) : (i += 1) {
            var map = self.array[i];
            map.free();
        }

        allocator.free(self.array);
    }
};

pub const set16 = struct {
    array: []u16,
    size: usize,

    pub fn new(init_cap: usize) !set16 {
        const arr = try allocator.alloc(u16, init_cap);
        return set16{ .array = arr, .size = 0 };
    }

    pub fn at(self: set16, index: usize) u16 {
        return self.array[index];
    }

    fn realloc(self: *set16, new_size: usize) !void {
        const new_arr: []u16 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn u16Order(a: u16, b: u16) std.math.Order {
        return std.math.order(a, b);
    }

    pub fn ins(self: *set16, value: u16) !void {
        const find = std.sort.binarySearch(u16, self.array[0..self.size], value, u16Order);
        if (find == null) {
            if (self.size >= self.array.len) {
                try self.realloc(self.array.len * 2 + 1);
            }
            const ins_ind = std.sort.lowerBound(u16, self.array[0..self.size], value, u16Order);
            const move_bytes = self.size - ins_ind;
            @memmove(self.array[ins_ind + 1 .. ins_ind + 1 + move_bytes], self.array[ins_ind .. ins_ind + move_bytes]);
            self.array[ins_ind] = value;
            self.size += 1;
        }
    }

    pub fn has(self: set16, value: u16) bool {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            if (self.array[i] == value) {
                return true;
            }
        }
        return false;
    }

    pub fn free(self: set16) void {
        allocator.free(self.array);
    }
};

pub const set64 = struct {
    array: []u64,
    size: usize,

    pub fn new(init_cap: usize) !set64 {
        const arr = try allocator.alloc(u64, init_cap);
        return set64{ .array = arr, .size = 0 };
    }

    fn realloc(self: *set64, new_size: usize) !void {
        const new_arr: []u64 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    fn u64Order(a: u64, b: u64) std.math.Order {
        return std.math.order(a, b);
    }

    pub fn ins(self: *set64, value: u64) !void {
        const find = std.sort.binarySearch(u64, self.array[0..self.size], value, u64Order);
        if (find == null) {
            if (self.size >= self.array.len) {
                try self.realloc(self.array.len * 2 + 1);
            }
            const ins_ind = std.sort.lowerBound(u64, self.array[0..self.size], value, u64Order);
            const move_bytes = self.size - ins_ind;
            @memmove(self.array[ins_ind + 1 .. ins_ind + 1 + move_bytes], self.array[ins_ind .. ins_ind + move_bytes]);
            self.array[ins_ind] = value;
            self.size += 1;
        }
    }

    pub fn has(self: set64, value: u64) bool {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            if (self.array[i] == value) {
                return true;
            }
        }
        return false;
    }

    pub fn free(self: set64) void {
        allocator.free(self.array);
    }
};

pub const set128 = struct {
    array: []u128,
    size: usize,

    pub fn new(init_cap: usize) !set128 {
        const arr = try allocator.alloc(u128, init_cap);
        return set128{ .array = arr, .size = 0 };
    }

    fn realloc(self: *set128, new_size: usize) !void {
        const new_arr: []u128 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    fn u128Order(a: u128, b: u128) std.math.Order {
        return std.math.order(a, b);
    }

    pub fn ins(self: *set128, value: u128) !void {
        const find = std.sort.binarySearch(u128, self.array[0..self.size], value, u128Order);
        if (find == null) {
            if (self.size >= self.array.len) {
                try self.realloc(self.array.len * 2 + 1);
            }
            const ins_ind = std.sort.lowerBound(u128, self.array[0..self.size], value, u128Order);
            const move_bytes = self.size - ins_ind;
            @memmove(self.array[ins_ind + 1 .. ins_ind + 1 + move_bytes], self.array[ins_ind .. ins_ind + move_bytes]);
            self.array[ins_ind] = value;
            self.size += 1;
        }
    }

    pub fn has(self: set128, value: u128) bool {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            if (self.array[i] == value) {
                return true;
            }
        }
        return false;
    }

    pub fn free(self: set128) void {
        allocator.free(self.array);
    }
};
