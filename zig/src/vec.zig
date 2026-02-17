const std = @import("std");

pub var allocator: std.mem.Allocator = undefined;

pub fn set_alloc(alloc: std.mem.Allocator) void {
    allocator = alloc;
}

pub const vec8 = struct {
    array: []u8,

    pub fn new(size: usize) !vec8 {
        const arr = try allocator.alloc(u8, size);
        return vec8{ .array = arr };
    }

    pub fn fill(self: vec8, value: u8) void {
        @memset(self.array, value);
    }

    pub fn realloc(self: *vec8, new_size: usize) !void {
        const new_arr: []u8 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn at(self: vec8, index: usize) u8 {
        return self.array[index];
    }

    pub fn set(self: vec8, index: usize, value: u8) void {
        self.array[index] = value;
    }

    pub fn free(self: *vec8) void {
        allocator.free(self.array);
    }
};

pub const vec16 = struct {
    array: []u16,

    pub fn new(size: usize) !vec16 {
        const arr = try allocator.alloc(u16, size);
        return vec16{ .array = arr };
    }

    pub fn at(self: vec16, index: usize) u16 {
        return self.array[index];
    }

    pub fn set(self: vec16, index: usize, value: u16) void {
        self.array[index] = value;
    }

    pub fn next(self: vec16, current: u16) u16 {
        for (self.array, 0..) |_, i| {
            if (self.array[i] == current) {
                return self.array[i + 1];
            }
        }
        unreachable;
    }

    pub fn free(self: vec16) void {
        allocator.free(self.array);
    }
};

pub const vec64 = struct {
    array: []u64,

    pub fn new(size: usize) !vec64 {
        const arr = try allocator.alloc(u64, size);
        @memset(arr, 0);
        return vec64{ .array = arr };
    }

    pub fn at(self: vec64, index: usize) u64 {
        return self.array[index];
    }
};

pub const vecbool = struct {
    array: []bool,

    pub fn new(size: usize, fill: u8) !vecbool {
        const arr = try allocator.alloc(bool, size);
        @memset(arr, false);
        @memset(arr[0..fill], true);
        return vecbool{ .array = arr };
    }

    pub fn at(self: vecbool, index: usize) bool {
        return self.array[index];
    }

    fn iter_swap(a: [*]bool, b: [*]bool) void {
        const temp = a.*;
        a.* = b.*;
        b.* = temp;
    }
    fn reverse(first: [*]bool, last: [*]bool) void {
        while (first != last and first != --last) {
            iter_swap(first, last);
            first += 1;
        }
    }

    pub fn prevperm(self: *vecbool) bool {
        if (self.array.len <= 1) return false;

        var i: usize = self.array.len - 1;
        while (i > 0 and (!self.array[i - 1] or self.array[i])) {
            i -= 1;
        }

        if (i == 0) {
            std.mem.reverse(bool, self.array);
            return false;
        }

        var j: usize = self.array.len - 1;
        while (self.array[j] or !self.array[i - 1]) {
            j -= 1;
        }

        std.mem.swap(bool, &self.array[i - 1], &self.array[j]);
        std.mem.reverse(bool, self.array[i..self.array.len]);

        return true;
    }

    pub fn free(self: vecbool) void {
        allocator.free(self.array);
    }
};

pub const neis = struct {
    cells: [8]u16,
    size: u8,

    pub fn at(self: neis, index: usize) u16 {
        return self.cells[index];
    }

    pub fn add(self: *neis, value: u16) void {
        self.cells[self.size] = value;
        self.size += 1;
    }
};

pub const vecneis = struct {
    array: []neis,
    size: usize,

    pub fn new(size: usize) !vecneis {
        const arr = try allocator.alloc(neis, size);
        return vecneis{ .array = arr, .size = 0 };
    }

    pub fn at(self: vecneis, index: usize) neis {
        return self.array[index];
    }

    pub fn add(self: *vecneis, value: neis) void {
        self.array[self.size] = value;
        self.size += 1;
    }

    pub fn add3(self: *vecneis, x: u16, y: u16, z: u16) void {
        const n = neis{ .cells = [8]u16{ x, y, z, 0, 0, 0, 0, 0 }, .size = 3 };
        self.add(n);
    }
    pub fn add5(self: *vecneis, x: u16, y: u16, z: u16, w: u16, v: u16) void {
        const n = neis{ .cells = [8]u16{ x, y, z, w, v, 0, 0, 0 }, .size = 5 };
        self.add(n);
    }
    pub fn add8(self: *vecneis, x: u16, y: u16, z: u16, w: u16, v: u16, u: u16, t: u16, s: u16) void {
        const n = neis{ .cells = [8]u16{ x, y, z, w, v, u, t, s }, .size = 8 };
        self.add(n);
    }

    pub fn free(self: *vecneis) void {
        allocator.free(self.array);
    }
};

pub const dvec8 = struct {
    array: []u8,
    size: usize,

    pub fn new(init_cap: usize) !dvec8 {
        const arr = try allocator.alloc(u8, init_cap);
        return dvec8{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvec8, index: usize) u8 {
        return self.array[index];
    }

    pub fn realloc(self: *dvec8, new_size: usize) !void {
        const new_arr: []u8 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvec8, value: u8) void {
        if (self.size >= self.array.len) {
            self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = value;
        self.size += 1;
    }

    pub fn free(self: dvec8) void {
        allocator.free(self.array);
    }
};

pub const dvec16 = struct {
    array: []u16,
    size: usize,

    pub fn new(init_cap: usize) !dvec16 {
        const arr = try allocator.alloc(u16, init_cap);
        return dvec16{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvec16, index: usize) u16 {
        return self.array[index];
    }

    pub fn realloc(self: *dvec16, new_size: usize) !void {
        const new_arr: []u16 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvec16, value: u16) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = value;
        self.size += 1;
    }

    pub fn has(self: dvec16, value: u16) bool {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            if (self.array[i] == value) {
                return true;
            }
        }
        return false;
    }

    pub fn index_of(self: dvec16, value: u16) usize {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            if (self.array[i] == value) {
                return i;
            }
        }
        return std.math.maxInt(usize);
    }

    pub fn clear(self: *dvec16) void {
        self.size = 0;
    }

    pub fn free(self: dvec16) void {
        allocator.free(self.array);
    }
};

pub const dvec64 = struct {
    array: []u64,
    size: usize,

    pub fn new(init_cap: usize) !dvec64 {
        const arr = try allocator.alloc(u64, init_cap);
        return dvec64{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvec64, index: usize) u64 {
        return self.array[index];
    }

    pub fn realloc(self: *dvec64, new_size: usize) !void {
        const new_arr: []u64 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvec64, value: u64) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = value;
        self.size += 1;
    }

    pub fn has(self: dvec64, value: u64) bool {
        for (self.array, 0..self.size) |_, i| {
            if (self.array[i] == value) {
                return true;
            }
        }
        return false;
    }
};

pub const dvec128 = struct {
    array: []u128,
    size: usize,

    pub fn new(init_cap: usize) !dvec128 {
        const arr = try allocator.alloc(u128, init_cap);
        return dvec128{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvec128, index: usize) u128 {
        return self.array[index];
    }

    pub fn realloc(self: *dvec128, new_size: usize) !void {
        const new_arr: []u128 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvec128, value: u128) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = value;
        self.size += 1;
    }

    pub fn has(self: dvec128, value: u128) bool {
        for (self.array, 0..self.size) |_, i| {
            if (self.array[i] == value) {
                return true;
            }
        }
        return false;
    }
};

pub const dvecvec64 = struct {
    array: []vec64,
    size: usize,

    pub fn new(init_cap: usize) !dvecvec64 {
        const arr = try allocator.alloc(vec64, init_cap);
        return dvecvec64{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvecvec64, index: usize) vec64 {
        return self.array[index];
    }

    pub fn realloc(self: *dvecvec64, new_size: usize) !void {
        const new_arr: []vec64 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvecvec64, value: vec64) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = value;
        self.size += 1;
    }
};

pub const pair16_8 = struct {
    first: u16,
    second: u8,
};

pub const dvecpair16_8 = struct {
    array: []pair16_8,
    size: usize,

    pub fn new(init_cap: usize) !dvecpair16_8 {
        const arr = try allocator.alloc(pair16_8, init_cap);
        return dvecpair16_8{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvecpair16_8, index: usize) pair16_8 {
        return self.array[index];
    }

    pub fn realloc(self: *dvecpair16_8, new_size: usize) !void {
        const new_arr: []pair16_8 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvecpair16_8, value: pair16_8) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = value;
        self.size += 1;
    }

    pub fn ins(self: *dvecpair16_8, pos: usize, value: pair16_8) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        var i = self.size;
        while (i > pos) : (i -= 1) {
            self.array[i] = self.array[i - 1];
        }
        self.array[pos] = value;
        self.size += 1;
    }

    pub fn clear(self: *dvecpair16_8) void {
        self.size = 0;
    }

    pub fn free(self: *dvecpair16_8) void {
        allocator.free(self.array);
    }
};

pub const pair64_8 = struct {
    first: u64,
    second: u8,
};

pub const pair128_8 = struct {
    first: u128,
    second: u8,
};

pub const pairdvec16_dvecpair16_8 = struct {
    first: dvec16,
    second: dvecpair16_8,
};

pub const dvecpairdvec16_dvecpair16_8 = struct {
    array: []pairdvec16_dvecpair16_8,
    size: usize,

    pub fn new(init_cap: usize) !dvecpairdvec16_dvecpair16_8 {
        const arr = try allocator.alloc(pairdvec16_dvecpair16_8, init_cap);
        return dvecpairdvec16_dvecpair16_8{ .array = arr, .size = 0 };
    }

    pub fn at(self: dvecpairdvec16_dvecpair16_8, index: usize) pairdvec16_dvecpair16_8 {
        return self.array[index];
    }

    pub fn realloc(self: *dvecpairdvec16_dvecpair16_8, new_size: usize) !void {
        const new_arr: []pairdvec16_dvecpair16_8 = try allocator.realloc(self.array, new_size);
        self.array = new_arr;
    }

    pub fn add(self: *dvecpairdvec16_dvecpair16_8, first: dvec16, second: dvecpair16_8) !void {
        if (self.size >= self.array.len) {
            try self.realloc(self.array.len * 2 + 1);
        }
        self.array[self.size] = pairdvec16_dvecpair16_8{ .first = first, .second = second };
        self.size += 1;
    }

    pub fn free(self: *dvecpairdvec16_dvecpair16_8) void {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            const pair = self.array[i];
            allocator.free(pair.first.array);
            allocator.free(pair.second.array);
        }
        allocator.free(self.array);
    }
};
