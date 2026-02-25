const std = @import("std");
const stl = @import("stl");
const vec = stl.vec;
const map = stl.map;

const LIMIT_BRUTE_FORCE = 10;

const vector = struct {
    ptr: *anyopaque,
    size: usize,
    cap: usize,

    pub fn get_as_u64(self: *const vector) vec.dvec64 {
        const ptr64: [*]u64 = @ptrCast(@alignCast(self.ptr));
        const slice = ptr64[0..self.cap];
        return vec.dvec64{ .array = slice, .size = self.size };
    }

    pub fn put_as_u64(input: *const vec.dvec64) vector {
        const ptr: *anyopaque = @ptrCast(@alignCast(input.array.ptr));
        return vector{ .ptr = ptr, .size = input.size, .cap = input.array.len };
    }

    pub fn get_as_u128(self: *const vector) vec.dvec128 {
        const ptr128: [*]u128 = @ptrCast(@alignCast(self.ptr));
        const slice = ptr128[0..self.cap];
        return vec.dvec128{ .array = slice, .size = self.size };
    }
    pub fn put_as_u128(input: *const vec.dvec128) vector {
        const ptr: *anyopaque = @ptrCast(@alignCast(input.array.ptr));
        return vector{ .ptr = ptr, .size = input.size, .cap = input.array.len };
    }
};

const NumCellInfo = struct {
    combs: ?vector,
    low: u64,
    high: u64,
    constraints: map.miniset16,
    mines: u8,
};

const NumTable = struct {
    table: []NumCellInfo,
    size: usize,

    pub fn init(size: usize) !NumTable {
        const tab = NumTable{
            .table = try vec.allocator.alloc(NumCellInfo, size),
            .size = size,
        };
        for (tab.table) |*info| {
            info.combs = null;
        }
        return tab;
    }

    pub fn set_mask_mines64(self: *NumTable, num: u16, mask: u64, mines: u8) void {
        self.table[num].low = mask;
        self.table[num].mines = mines;
    }

    pub fn set_mask_mines128(self: *NumTable, num: u16, mask: u128, mines: u8) void {
        self.table[num].low = @truncate(mask);
        self.table[num].high = @truncate(mask >> 64);
        self.table[num].mines = mines;
    }

    pub fn set_constraints(self: *NumTable, num: u16, constraints: map.miniset16) void {
        self.table[num].constraints = constraints;
    }

    pub fn set_combs64(self: *NumTable, num: u16, combs: vec.dvec64) void {
        if (self.table[num].combs) |c| {
            const cc: vec.dvec64 = c.get_as_u64();
            vec.allocator.free(cc.array);
        }
        self.table[num].combs = vector.put_as_u64(&combs);
    }

    pub fn set_combs128(self: *NumTable, num: u16, combs: vec.dvec128) void {
        if (self.table[num].combs) |c| {
            const cc: vec.dvec64 = c.get_as_u64();
            vec.allocator.free(cc.array);
        }
        self.table[num].combs = vector.put_as_u128(&combs);
    }

    pub fn get_combs64(self: *NumTable, num: u16) vec.dvec64 {
        return self.table[num].combs.?.get_as_u64();
    }

    pub fn get_combs128(self: *NumTable, num: u16) vec.dvec128 {
        return self.table[num].combs.?.get_as_u128();
    }

    pub fn get_constraints(self: *NumTable, num: u16) map.miniset16 {
        return self.table[num].constraints;
    }

    pub fn get_mask_mines64(self: *NumTable, num: u16) vec.pair64_8 {
        return vec.pair64_8{
            .first = self.table[num].low,
            .second = self.table[num].mines,
        };
    }
    pub fn get_mask_mines128(self: *NumTable, num: u16) vec.pair128_8 {
        return vec.pair128_8{
            .first = @as(u128, self.table[num].low | @as(u128, self.table[num].high) << 64),
            .second = self.table[num].mines,
        };
    }

    pub fn deinit(self: *NumTable) void {
        for (self.table[0..self.size]) |*info| {
            const v = info.combs;
            if (v) |c| {
                const cc = c.get_as_u64();
                vec.allocator.free(cc.array);
            }
        }
        vec.allocator.free(self.table);
    }
};

var input_field: vec.vec8 = undefined;
var game_field: vec.vec8 = undefined;
var temp_field: vec.vec8 = undefined;
var field_size: u16 = undefined;
var real_size: u16 = undefined;
pub var field_width: u8 = undefined;
pub var field_height: u8 = undefined;
var remain_mines: u16 = undefined;
pub var total_mines: u16 = undefined;
var last_number: u16 = undefined;
var edge_cells_list: vec.dvec16 = undefined;
var edge_cells_count: u16 = undefined;
var num_cells_list: vec.dvecpair16_8 = undefined;
var float_cells_list: vec.dvec16 = undefined;
var float_cells_count: u16 = undefined;
var num_table: NumTable = undefined;
var neis_cache: vec.vecneis = undefined;
var popcnts: [1 << LIMIT_BRUTE_FORCE]u8 = undefined;

pub fn init(w: u8, h: u8, m: u16) !void {
    total_mines = m;
    field_width = w;
    field_height = h;
    field_size = @as(u16, w) * h;
    real_size = @as(u16, w) * h;
    input_field = try vec.vec8.new(@as(u16, w) * h);
    game_field = try vec.vec8.new(@as(u16, w) * h);
    temp_field = try vec.vec8.new(@as(u16, w) * h);
    edge_cells_list = try vec.dvec16.new(10);
    edge_cells_count = 0;
    num_cells_list = try vec.dvecpair16_8.new(10);
    float_cells_list = try vec.dvec16.new(10);
    float_cells_count = 0;
    remain_mines = 0;
    last_number = 0;

    fillpopcnts();
    num_table = try NumTable.init(field_size);
    try set_neis_cache();
}

pub fn resize(new_w: u8, new_h: u8, new_m: u16) !void {
    num_table.deinit();
    field_width = new_w;
    field_height = new_h;
    total_mines = new_m;
    field_size = @as(u16, new_w) * new_h;
    real_size = @as(u16, new_w) * new_h;
    try input_field.realloc(real_size);
    try game_field.realloc(real_size);
    try temp_field.realloc(real_size);
    num_table = try NumTable.init(field_size);
    neis_cache.free();
    try set_neis_cache();
}

pub fn deinit() void {
    input_field.free();
    game_field.free();
    temp_field.free();
    edge_cells_list.free();
    num_cells_list.free();
    float_cells_list.free();
    num_table.deinit();
}

pub fn get_input_ptr() [*]u8 {
    return input_field.array.ptr;
}
pub fn get_input_len() usize {
    return input_field.array.len;
}

pub fn get_probs_ptr() [*]u8 {
    return game_field.array.ptr;
}
pub fn get_probs_len() usize {
    return game_field.array.len;
}

fn set_neis_cache() !void {
    neis_cache = try vec.vecneis.new(field_size);
    const fw = field_width;
    for (0..field_size) |cc| {
        const c: u16 = @intCast(cc);
        const row = c / fw;
        const col = c % fw;

        if (row == 0) {
            if (col == 0) {
                neis_cache.add3(1, fw, fw + 1);
            } else if (col == fw - 1) {
                neis_cache.add3(c - 1, c + fw - 1, c + fw);
            } else {
                neis_cache.add5(c - 1, c + 1, c + fw - 1, c + fw, c + 1 + fw);
            }
        } else if (row == field_height - 1) {
            if (col == 0) {
                neis_cache.add3(c - fw, c + 1 - fw, c + 1);
            } else if (col == fw - 1) {
                neis_cache.add3(c - 1, c - 1 - fw, c - fw);
            } else {
                neis_cache.add5(c - 1, c + 1, c + 1 - fw, c - 1 - fw, c - fw);
            }
        } else {
            if (col == 0) {
                neis_cache.add5(c - fw, c + 1 - fw, c + 1, c + fw, c + fw + 1);
            } else if (col == fw - 1) {
                neis_cache.add5(c - 1 - fw, c - fw, c - 1, c - 1 + fw, c + fw);
            } else {
                neis_cache.add8(c - 1 - fw, c - fw, c + 1 - fw, c - 1, c + 1, c - 1 + fw, c + fw, c + fw + 1);
            }
        }
    }
}

fn fillpopcnts() void {
    popcnts[0] = 0;
    const limit = 1 << LIMIT_BRUTE_FORCE;
    for (0..limit) |i| {
        const last: u8 = @truncate(i);
        popcnts[i] = (last & 1) + popcnts[i >> 1];
    }
}

fn get_neis(c: u16) vec.neis {
    return neis_cache.at(c);
}

fn set_flags_and_float_cells() !void {
    temp_field.fill(26);
    const f = game_field.array;
    for (game_field.array[0..field_size], 0..field_size) |gameval, i| {
        const neighbors = get_neis(@truncate(i));
        var closed_count: u8 = 0;
        const n = neighbors.cells;
        switch (neighbors.size) {
            8 => {
                @branchHint(.likely);
                closed_count = @as(u8, @intFromBool(f[n[0]] == 9)) + @as(u8, @intFromBool(f[n[1]] == 9)) +
                    @as(u8, @intFromBool(f[n[2]] == 9)) + @as(u8, @intFromBool(f[n[3]] == 9)) +
                    @as(u8, @intFromBool(f[n[4]] == 9)) + @as(u8, @intFromBool(f[n[5]] == 9)) +
                    @as(u8, @intFromBool(f[n[6]] == 9)) + @as(u8, @intFromBool(f[n[7]] == 9));
            },
            5 => {
                closed_count = @as(u8, @intFromBool(f[n[0]] == 9)) + @as(u8, @intFromBool(f[n[1]] == 9)) +
                    @as(u8, @intFromBool(f[n[2]] == 9)) + @as(u8, @intFromBool(f[n[3]] == 9)) +
                    @as(u8, @intFromBool(f[n[4]] == 9));
            },
            3 => {
                closed_count = @as(u8, @intFromBool(f[n[0]] == 9)) + @as(u8, @intFromBool(f[n[1]] == 9)) +
                    @as(u8, @intFromBool(f[n[2]] == 9));
            },
            else => {
                unreachable;
            },
        }
        if (gameval == 9 and closed_count == neighbors.size) {
            try float_cells_list.add(@truncate(i));
            temp_field.set(i, 26);
        } else if (gameval > 0 and gameval < 9 and gameval == closed_count) {
            switch (neighbors.size) {
                8 => {
                    @branchHint(.likely);
                    if (f[n[0]] == 9) {
                        temp_field.set(n[0], 11);
                    } else {
                        temp_field.set(n[0], f[n[0]]);
                    }
                    if (f[n[1]] == 9) {
                        temp_field.set(n[1], 11);
                    } else {
                        temp_field.set(n[1], f[n[1]]);
                    }
                    if (f[n[2]] == 9) {
                        temp_field.set(n[2], 11);
                    } else {
                        temp_field.set(n[2], f[n[2]]);
                    }
                    if (f[n[3]] == 9) {
                        temp_field.set(n[3], 11);
                    } else {
                        temp_field.set(n[3], f[n[3]]);
                    }
                    if (f[n[4]] == 9) {
                        temp_field.set(n[4], 11);
                    } else {
                        temp_field.set(n[4], f[n[4]]);
                    }
                    if (f[n[5]] == 9) {
                        temp_field.set(n[5], 11);
                    } else {
                        temp_field.set(n[5], f[n[5]]);
                    }
                    if (f[n[6]] == 9) {
                        temp_field.set(n[6], 11);
                    } else {
                        temp_field.set(n[6], f[n[6]]);
                    }
                    if (f[n[7]] == 9) {
                        temp_field.set(n[7], 11);
                    } else {
                        temp_field.set(n[7], f[n[7]]);
                    }
                },
                5 => {
                    if (f[n[0]] == 9) {
                        temp_field.set(n[0], 11);
                    } else {
                        temp_field.set(n[0], f[n[0]]);
                    }
                    if (f[n[1]] == 9) {
                        temp_field.set(n[1], 11);
                    } else {
                        temp_field.set(n[1], f[n[1]]);
                    }
                    if (f[n[2]] == 9) {
                        temp_field.set(n[2], 11);
                    } else {
                        temp_field.set(n[2], f[n[2]]);
                    }
                    if (f[n[3]] == 9) {
                        temp_field.set(n[3], 11);
                    } else {
                        temp_field.set(n[3], f[n[3]]);
                    }
                    if (f[n[4]] == 9) {
                        temp_field.set(n[4], 11);
                    } else {
                        temp_field.set(n[4], f[n[4]]);
                    }
                },
                3 => {
                    if (f[n[0]] == 9) {
                        temp_field.set(n[0], 11);
                    } else {
                        temp_field.set(n[0], f[n[0]]);
                    }
                    if (f[n[1]] == 9) {
                        temp_field.set(n[1], 11);
                    } else {
                        temp_field.set(n[1], f[n[1]]);
                    }
                    if (f[n[2]] == 9) {
                        temp_field.set(n[2], 11);
                    } else {
                        temp_field.set(n[2], f[n[2]]);
                    }
                },
                else => {
                    unreachable;
                },
            }
            temp_field.set(i, gameval);
        } else if (temp_field.at(i) != 11) {
            temp_field.set(i, gameval);
        }
    }
    @memcpy(game_field.array, temp_field.array);
    float_cells_count = @truncate(float_cells_list.size);
}

fn set_safe_and_number_cells() !void {
    var flag_count: u16 = 0;
    const f = game_field.array;
    for (game_field.array[0..field_size], 0..field_size) |gameval, i| {
        if (gameval < 9) {
            const neighbors = get_neis(@truncate(i));
            const n = neighbors.cells;
            var flags_count: u8 = 0;
            switch (neighbors.size) {
                8 => {
                    @branchHint(.likely);
                    flags_count = @as(u8, @intFromBool(f[n[0]] == 11)) + @as(u8, @intFromBool(f[n[1]] == 11)) +
                        @as(u8, @intFromBool(f[n[2]] == 11)) + @as(u8, @intFromBool(f[n[3]] == 11)) +
                        @as(u8, @intFromBool(f[n[4]] == 11)) + @as(u8, @intFromBool(f[n[5]] == 11)) +
                        @as(u8, @intFromBool(f[n[6]] == 11)) + @as(u8, @intFromBool(f[n[7]] == 11));
                    if (gameval == flags_count) {
                        if (f[n[0]] == 9) temp_field.set(n[0], 27);
                        if (f[n[1]] == 9) temp_field.set(n[1], 27);
                        if (f[n[2]] == 9) temp_field.set(n[2], 27);
                        if (f[n[3]] == 9) temp_field.set(n[3], 27);
                        if (f[n[4]] == 9) temp_field.set(n[4], 27);
                        if (f[n[5]] == 9) temp_field.set(n[5], 27);
                        if (f[n[6]] == 9) temp_field.set(n[6], 27);
                        if (f[n[7]] == 9) temp_field.set(n[7], 27);
                    } else {
                        try num_cells_list.add(vec.pair16_8{ .first = @truncate(i), .second = (gameval - flags_count) });
                    }
                },
                5 => {
                    flags_count = @as(u8, @intFromBool(f[n[0]] == 11)) + @as(u8, @intFromBool(f[n[1]] == 11)) +
                        @as(u8, @intFromBool(f[n[2]] == 11)) + @as(u8, @intFromBool(f[n[3]] == 11)) +
                        @as(u8, @intFromBool(f[n[4]] == 11));
                    if (gameval == flags_count) {
                        if (f[n[0]] == 9) temp_field.set(n[0], 27);
                        if (f[n[1]] == 9) temp_field.set(n[1], 27);
                        if (f[n[2]] == 9) temp_field.set(n[2], 27);
                        if (f[n[3]] == 9) temp_field.set(n[3], 27);
                        if (f[n[4]] == 9) temp_field.set(n[4], 27);
                    } else {
                        try num_cells_list.add(vec.pair16_8{ .first = @truncate(i), .second = (gameval - flags_count) });
                    }
                },
                3 => {
                    flags_count = @as(u8, @intFromBool(f[n[0]] == 11)) + @as(u8, @intFromBool(f[n[1]] == 11)) +
                        @as(u8, @intFromBool(f[n[2]] == 11));
                    if (gameval == flags_count) {
                        if (f[n[0]] == 9) temp_field.set(n[0], 27);
                        if (f[n[1]] == 9) temp_field.set(n[1], 27);
                        if (f[n[2]] == 9) temp_field.set(n[2], 27);
                    } else {
                        try num_cells_list.add(vec.pair16_8{ .first = @truncate(i), .second = (gameval - flags_count) });
                    }
                },
                else => {
                    unreachable;
                },
            }
        } else if (gameval == 11) {
            flag_count += 1;
        }
    }
    @memcpy(game_field.array[0..field_size], temp_field.array[0..field_size]);
    remain_mines = total_mines - flag_count;
}

fn set_edge_cells() !void {
    for (game_field.array[0..field_size], 0..field_size) |gval, i| {
        if (gval == 9) {
            try edge_cells_list.add(@truncate(i));
        }
    }
    edge_cells_count = @truncate(edge_cells_list.size);
}

fn check_if_27() bool {
    var i: usize = 0;
    const p27: @Vector(16, u8) = @splat(27);
    while (i < real_size) : (i += 16) {
        const data: @Vector(16, u8) = game_field.array[i..][0..16].*;
        const eq = data == p27;
        const mask: u16 = @bitCast(eq);
        if (mask > 0) {
            return true;
        }
    }
    return false;
}

fn cell_to_bit(key: u16) u7 {
    const value = temp_field.at(key);
    return if (value != std.math.maxInt(u8))
        @truncate(value)
    else
        std.math.maxInt(u7);
}

fn get_cell_groups(groups: *vec.dvecpairdvec16_dvecpair16_8) !void {
    var checked_count: u16 = 0;

    while (checked_count < edge_cells_count) {
        var first_cell = edge_cells_list.at(0);

        if (groups.size != 0) {
            for (edge_cells_list.array[0..edge_cells_count]) |edge_cell| {
                var skip = false;
                outer: for (groups.array[0..groups.size]) |group| {
                    const group_edges = group.first;
                    for (group_edges.array[0..group_edges.size]) |group_edge| {
                        if (group_edge == edge_cell) {
                            skip = true;
                            break :outer;
                        }
                    }
                }
                if (!skip) {
                    first_cell = edge_cell;
                    break;
                }
            }
        }

        var edge_cells = try vec.dvec16.new(8);
        try edge_cells.add(first_cell);
        var num_cells = try vec.dvec16.new(8);
        defer num_cells.free();
        try make_cell_group(&edge_cells, &num_cells);

        var num_cells_with_counts = try vec.dvecpair16_8.new(num_cells_list.size);
        for (num_cells.array[0..num_cells.size], 0..num_cells.size) |num_cell, n| {
            for (num_cells_list.array[0..num_cells_list.size]) |list_num_cell| {
                if (num_cell == list_num_cell.first) {
                    try num_cells_with_counts.ins(n, list_num_cell);
                    break;
                }
            }
        }

        checked_count += @truncate(edge_cells.size);
        std.sort.block(u16, edge_cells.array[0..edge_cells.size], {}, std.sort.asc(u16));
        try groups.add(edge_cells, num_cells_with_counts);
    }
}

fn make_cell_group(edge_cells: *vec.dvec16, num_cells: *vec.dvec16) !void {
    var edges_checked: usize = 0;
    var nums_checked: usize = 0;
    while (true) {
        for (edges_checked..edge_cells.size) |i| {
            const neighbors = get_neis(edge_cells.at(i));
            for (0..neighbors.size) |j| {
                const nei_index = neighbors.at(j);
                if (game_field.at(nei_index) < 9 and !num_cells.has(nei_index)) {
                    try num_cells.add(nei_index);
                }
            }
            edges_checked += 1;
        }

        for (nums_checked..num_cells.size) |i| {
            const neighbors = get_neis(num_cells.at(i));
            for (0..neighbors.size) |j| {
                const nei_index = neighbors.at(j);
                if (game_field.at(nei_index) == 9 and !edge_cells.has(nei_index)) {
                    try edge_cells.add(nei_index);
                }
            }
            nums_checked += 1;
        }

        if (nums_checked == num_cells.size and edges_checked == edge_cells.size) {
            break;
        }
    }
}

fn edge_index(edge: u16, edge_cells: [*]u16, edge_size: usize) u8 {
    for (edge_cells[0..edge_size], 0..edge_size) |elem, i| {
        if (elem == edge) {
            return @truncate(i);
        }
    }
    return 31;
}

fn brute_force(edge_cells: *const vec.dvec16, num_cells: *const vec.dvecpair16_8, combs: *map.mapvec64) !void {
    const edge_size = edge_cells.size;
    var num_size = num_cells.size;
    var mapping: [LIMIT_BRUTE_FORCE]u8 = undefined;

    for (edge_cells.array[0..edge_size], 0..edge_size) |cell, i| {
        mapping[i] = edge_index(cell, edge_cells_list.array.ptr, edge_cells_count);
    }

    var seen_masks: [2 * LIMIT_BRUTE_FORCE]u16 = undefined;
    var temp_size: usize = 0;

    var border_info: [2 * LIMIT_BRUTE_FORCE]vec.pair16_8 = undefined;

    for (num_cells.array[0..num_size]) |num| {
        const num_index = num.first;
        const mine_count = num.second;
        const neighbors = get_neis(num_index);
        var mask0: u32 = 0;

        switch (neighbors.size) {
            8 => {
                mask0 |= (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(0), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(1), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(2), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(3), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(4), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(5), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(6), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(7), edge_cells.array.ptr, edge_size))));
            },
            5 => {
                mask0 |= (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(0), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(1), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(2), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(3), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(4), edge_cells.array.ptr, edge_size))));
            },
            3 => {
                mask0 |= (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(0), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(1), edge_cells.array.ptr, edge_size)))) |
                    (@as(u32, 1) << @as(u5, @truncate(edge_index(neighbors.at(2), edge_cells.array.ptr, edge_size))));
            },
            else => unreachable,
        }

        const mask: u16 = @truncate(mask0);

        var contains = false;
        for (seen_masks[0..temp_size]) |s| {
            if (s == mask) {
                contains = true;
                break;
            }
        }

        if (!contains) {
            seen_masks[temp_size] = mask;
            border_info[temp_size] = vec.pair16_8{ .first = mask, .second = mine_count };
            temp_size += 1;
        }
    }
    num_size = temp_size;
    var count_to_index: [LIMIT_BRUTE_FORCE]u8 = undefined;
    @memset(&count_to_index, std.math.maxInt(u8));
    var result: [5]vec.vec64 = undefined;
    var result_size: usize = 0;

    const limit: u16 = (@as(u16, 1) << @as(u4, @truncate(edge_size)));
    for (0..limit) |mask| {
        var valid = true;
        const bits = popcnts[mask];
        for (border_info[0..num_size]) |mask_mines| {
            const overlap = @as(u16, @truncate(mask)) & mask_mines.first;
            if (popcnts[overlap] != mask_mines.second) {
                valid = false;
                break;
            }
        }
        if (valid and bits <= remain_mines) {
            if (count_to_index[bits] == std.math.maxInt(u8)) {
                count_to_index[bits] = @truncate(result_size);
                const v = try vec.vec64.new(edge_cells_count + 1);
                result[result_size] = v;
                result_size += 1;
            }
            const ind = count_to_index[bits];
            var c = result[ind];
            var maskcpy: u16 = @truncate(mask);
            while (maskcpy > 0) {
                const t: u16 = @ctz(maskcpy);
                maskcpy &= maskcpy - 1;
                const ind2 = mapping[t];
                c.array[ind2] += 1;
            }
            c.array[edge_cells_count] += 1;
        }
    }

    for (0..LIMIT_BRUTE_FORCE) |bit_count| {
        const index = count_to_index[bit_count];
        if (index != std.math.maxInt(u8)) {
            const val = result[index];
            combs.set(bit_count, val);
        }
    }
}

fn find_all_combinations64(edge_cells: *const vec.dvec16, num_cells: *const vec.dvecpair16_8, combs: *map.mapvec64) !void {
    const edge_size = edge_cells.size;
    var num_size = num_cells.size;
    var mapping = try vec.vec8.new(edge_size);
    defer mapping.free();
    @memset(temp_field.array, std.math.maxInt(u8));

    for (edge_cells.array[0..edge_size], 0..edge_size) |cell, i| {
        const ind = std.sort.binarySearch(u16, edge_cells_list.array[0..edge_cells_list.size], cell, map.set16.u16Order).?;
        mapping.set(i, @truncate(ind));
        temp_field.set(cell, @truncate(i));
    }

    var seen_masks = try map.set64.new(num_size);
    defer seen_masks.free();
    var num_set = try map.set16.new(num_size);
    defer num_set.free();

    for (num_cells.array[0..num_size]) |num| {
        const cell_index = num.first;
        const mine_count = num.second;
        const neighbors = get_neis(cell_index);
        var mask0: u128 = 0;

        switch (neighbors.size) {
            8 => {
                mask0 |= (@as(u128, 1) << cell_to_bit(neighbors.at(0))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(1))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(2))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(3))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(4))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(5))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(6))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(7)));
            },
            5 => {
                mask0 |= (@as(u128, 1) << cell_to_bit(neighbors.at(0))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(1))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(2))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(3))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(4)));
            },
            3 => {
                mask0 |= (@as(u128, 1) << cell_to_bit(neighbors.at(0))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(1))) |
                    (@as(u128, 1) << cell_to_bit(neighbors.at(2)));
            },
            else => unreachable,
        }
        const mask: u64 = @truncate(mask0);

        if (!seen_masks.has(mask)) {
            try seen_masks.ins(mask);
            try num_set.ins(cell_index);
            var combos = try vec.dvec64.new(10);
            try bit_combs64(mask, mine_count, &combos);
            num_table.set_combs64(cell_index, combos);
            num_table.set_mask_mines64(cell_index, mask, @as(u8, @popCount(mask)) - mine_count);
        }
    }
    num_size = num_set.size;

    var edges_neis = try vec.vecneis.new(edge_size);
    defer edges_neis.free();
    for (edge_cells.array[0..edge_size]) |edge| {
        const neighbors = get_neis(edge);
        var edge_neis: vec.neis = undefined;
        edge_neis.size = 0;
        for (neighbors.cells[0..neighbors.size]) |nei| {
            if (num_set.has(nei)) {
                edge_neis.add(nei);
            }
        }
        edges_neis.add(edge_neis);
    }

    for (num_set.array[0..num_size]) |num| {
        const num_neighbors = get_neis(num);
        var constraints: map.miniset16 = undefined;
        constraints.size = 0;
        for (num_neighbors.cells[0..num_neighbors.size]) |nei| {
            const index = edge_cells.index_of(nei);
            if (index != std.math.maxInt(usize)) {
                const edges = edges_neis.at(index);
                for (edges.cells[0..edges.size]) |edge| {
                    constraints.ins(edge);
                }
            }
        }
        num_table.set_constraints(num, constraints);
    }

    const num_vec: vec.vec16 = vec.vec16{ .array = num_set.array };

    var count_to_index = try vec.vec8.new(edge_size + 1);
    defer count_to_index.free();
    count_to_index.fill(std.math.maxInt(u8));
    var result = try vec.dvecvec64.new(5);
    defer vec.allocator.free(result.array);

    last_number = num_vec.at(num_size - 1);
    try mine_combinations64(num_vec.at(0), 0, &num_vec, &count_to_index, &result, &mapping);

    for (0..edge_size) |bit_count| {
        const index = count_to_index.at(bit_count);
        if (index != std.math.maxInt(u8)) {
            const val = result.at(index);
            combs.set(bit_count, val);
        }
    }
}

fn bit_combs64(full_mask: u64, k: u8, result: *vec.dvec64) !void {
    var bit_pos: [64]u8 = undefined;
    var bit_size: usize = 0;
    for (0..64) |i| {
        if (full_mask & (@as(u64, 1) << @as(u6, @truncate(i))) > 0) {
            bit_pos[bit_size] = @truncate(i);
            bit_size += 1;
        }
    }
    const total: u8 = @truncate(bit_size);
    if (k > total) {
        return;
    }
    var selection = try vec.vecbool.new(total, k);
    defer selection.free();

    while (true) {
        var mask: u64 = 0;
        for (0..total) |j| {
            if (selection.at(j)) {
                mask |= @as(u64, 1) << @as(u6, @truncate(bit_pos[j]));
            }
        }
        try result.add(mask);
        if (!selection.prevperm()) {
            break;
        }
    }
}

fn mine_combinations64(current_number: u16, mask: u64, num_set: *const vec.vec16, count_to_index: *vec.vec8, result: *vec.dvecvec64, mapping: *const vec.vec8) !void {
    const constraints = num_table.get_constraints(current_number);
    const combs = num_table.get_combs64(current_number);

    for (combs.array[0..combs.size]) |combo| {
        const new_mask = mask | combo;
        var valid = true;

        for (constraints.data[0..constraints.size]) |constraint| {
            const mask_mine = num_table.get_mask_mines64(constraint);
            const constraint_mask = mask_mine.first;
            const mines = mask_mine.second;
            const different_bits: u8 = @popCount((new_mask ^ constraint_mask) & constraint_mask);

            if (different_bits < mines) {
                valid = false;
                break;
            }
        }

        if (valid) {
            if (current_number != last_number) {
                const next_number = num_set.next(current_number);
                try mine_combinations64(next_number, new_mask, num_set, count_to_index, result, mapping);
            } else {
                const bit_count: u8 = @popCount(new_mask);
                if (bit_count <= remain_mines) {
                    try add_combination64(new_mask, bit_count, count_to_index, result, mapping);
                }
            }
        }
    }
}

fn add_combination64(mask: u64, bit_count: u8, count_to_index: *vec.vec8, result: *vec.dvecvec64, mapping: *const vec.vec8) !void {
    if (count_to_index.at(bit_count) == std.math.maxInt(u8)) {
        count_to_index.set(bit_count, @truncate(result.size));
        const v = try vec.vec64.new(edge_cells_count + 1);
        try result.add(v);
    }
    const ind = count_to_index.at(bit_count);
    var c = result.at(ind);
    var maskcpy = mask;
    while (maskcpy > 0) {
        const t = @ctz(maskcpy);
        maskcpy &= maskcpy - 1;
        const ind2 = mapping.at(t);
        c.array[ind2] += 1;
    }
    c.array[edge_cells_count] += 1;
}

fn find_all_combinations128(edge_cells: *const vec.dvec16, num_cells: *const vec.dvecpair16_8, combs: *map.mapvec64) !void {
    const edge_size = edge_cells.size;
    var num_size = num_cells.size;
    var mapping = try vec.vec8.new(edge_size);
    defer mapping.free();
    @memset(temp_field.array, std.math.maxInt(u8));

    for (edge_cells.array[0..edge_size], 0..edge_size) |cell, i| {
        const ind = std.sort.binarySearch(u16, edge_cells_list.array[0..edge_cells_list.size], cell, map.set16.u16Order).?;
        mapping.set(i, @truncate(ind));
        temp_field.set(cell, @truncate(i));
    }

    var seen_masks = try map.set128.new(num_size);
    defer seen_masks.free();
    var num_set = try map.set16.new(num_size);
    defer num_set.free();

    for (num_cells.array[0..num_size]) |num| {
        const cell_index = num.first;
        const mine_count = num.second;
        const neighbors = get_neis(cell_index);
        var mask: u128 = 0;

        for (neighbors.cells[0..neighbors.size]) |nei_index| {
            const val = cell_to_bit(nei_index);
            if (val != 127) {
                mask |= (@as(u128, 1) << val);
            }
        }

        if (!seen_masks.has(mask)) {
            try seen_masks.ins(mask);
            try num_set.ins(cell_index);
            var combos = try vec.dvec128.new(10);
            try bit_combs128(mask, mine_count, &combos);
            num_table.set_combs128(cell_index, combos);
            num_table.set_mask_mines128(cell_index, mask, @as(u8, @popCount(mask)) - mine_count);
        }
    }
    num_size = num_set.size;

    var edges_neis = try vec.vecneis.new(edge_size);
    defer edges_neis.free();
    for (edge_cells.array[0..edge_size]) |edge| {
        const neighbors = get_neis(edge);
        var edge_neis: vec.neis = undefined;
        edge_neis.size = 0;
        for (neighbors.cells[0..neighbors.size]) |nei| {
            if (num_set.has(nei)) {
                edge_neis.add(nei);
            }
        }
        edges_neis.add(edge_neis);
    }

    for (num_set.array[0..num_size]) |num| {
        const num_neighbors = get_neis(num);
        var constraints: map.miniset16 = undefined;
        constraints.size = 0;
        for (num_neighbors.cells[0..num_neighbors.size]) |nei| {
            const index = edge_cells.index_of(nei);
            if (index != std.math.maxInt(usize)) {
                const edges = edges_neis.at(index);
                for (edges.cells[0..edges.size]) |edge| {
                    constraints.ins(edge);
                }
            }
        }
        num_table.set_constraints(num, constraints);
    }

    const num_vec: vec.vec16 = vec.vec16{ .array = num_set.array };

    var count_to_index = try vec.vec8.new(edge_size + 1);
    defer count_to_index.free();
    count_to_index.fill(std.math.maxInt(u8));
    var result = try vec.dvecvec64.new(5);
    defer vec.allocator.free(result.array);

    last_number = num_vec.at(num_size - 1);
    try mine_combinations128(num_vec.at(0), 0, &num_vec, &count_to_index, &result, &mapping);

    for (0..edge_size) |bit_count| {
        const index = count_to_index.at(bit_count);
        if (index != std.math.maxInt(u8)) {
            const val = result.at(index);
            combs.set(bit_count, val);
        }
    }
}

fn bit_combs128(full_mask: u128, k: u8, result: *vec.dvec128) !void {
    var bit_pos: [128]u8 = undefined;
    var bit_size: usize = 0;
    for (0..128) |i| {
        if (full_mask & (@as(u128, 1) << @as(u7, @truncate(i))) > 0) {
            bit_pos[bit_size] = @truncate(i);
            bit_size += 1;
        }
    }
    const total: u8 = @truncate(bit_size);
    if (k > total) {
        return;
    }
    var selection = try vec.vecbool.new(total, k);
    defer selection.free();

    while (true) {
        var mask: u128 = 0;
        for (0..total) |j| {
            if (selection.at(j)) {
                mask |= @as(u128, 1) << @as(u7, @truncate(bit_pos[j]));
            }
        }
        try result.add(mask);
        if (!selection.prevperm()) {
            break;
        }
    }
}

fn mine_combinations128(current_number: u16, mask: u128, num_set: *const vec.vec16, count_to_index: *vec.vec8, result: *vec.dvecvec64, mapping: *const vec.vec8) !void {
    const constraints = num_table.get_constraints(current_number);
    const combs = num_table.get_combs128(current_number);

    for (combs.array[0..combs.size]) |combo| {
        const new_mask = mask | combo;
        var valid = true;

        for (constraints.data[0..constraints.size]) |constraint| {
            const mask_mine = num_table.get_mask_mines128(constraint);
            const constraint_mask = mask_mine.first;
            const mines = mask_mine.second;
            const different_bits: u8 = @popCount((new_mask ^ constraint_mask) & constraint_mask);

            if (different_bits < mines) {
                valid = false;
                break;
            }
        }

        if (valid) {
            if (current_number != last_number) {
                const next_number = num_set.next(current_number);
                try mine_combinations128(next_number, new_mask, num_set, count_to_index, result, mapping);
            } else {
                const bit_count: u8 = @popCount(new_mask);
                if (bit_count <= remain_mines) {
                    try add_combination128(new_mask, bit_count, count_to_index, result, mapping);
                }
            }
        }
    }
}

fn add_combination128(mask: u128, bit_count: u8, count_to_index: *vec.vec8, result: *vec.dvecvec64, mapping: *const vec.vec8) !void {
    if (count_to_index.at(bit_count) == std.math.maxInt(u8)) {
        count_to_index.set(bit_count, @truncate(result.size));
        const v = try vec.vec64.new(edge_cells_count + 1);
        try result.add(v);
    }
    const ind = count_to_index.at(bit_count);
    var c = result.at(ind);
    var low: u64 = @truncate(mask);
    while (low > 0) {
        const t = @ctz(low);
        low &= low - 1;
        const ind2 = mapping.at(t);
        c.array[ind2] += 1;
    }
    var high: u64 = @truncate(mask >> 64);
    while (high > 0) {
        const t = @ctz(high);
        high &= high - 1;
        const ind2 = mapping.at(t);
        c.array[ind2] += 1;
    }
    c.array[edge_cells_count] += 1;
}

fn create_occurrences_map(group_maps: *map.vecmapvec64, occurrences_map: *map.mapvec64) !void {
    var counts = try vec.vec8.new(group_maps.array.len);
    defer counts.free();
    counts.fill(0);
    try backtrack_occurrences(0, 0, group_maps, &counts, occurrences_map);
}

fn backtrack_occurrences(index: usize, mines: u16, group_maps: *map.vecmapvec64, counts: *vec.vec8, occurrences_map: *map.mapvec64) !void {
    if (mines > remain_mines) {
        return;
    }

    if (index == group_maps.array.len) {
        if (remain_mines - mines > float_cells_count) {
            return;
        }
        var factor: u64 = 1;
        for (0..group_maps.array.len) |group| {
            const mapvec = group_maps.at(group);
            const ind = counts.at(group);
            const v = mapvec.at(ind).?;
            const val = v.at(edge_cells_count);
            factor *= val;
        }
        var arr: vec.vec64 = occurrences_map.at(mines) orelse blk: {
            const new_array = try vec.vec64.new(edge_cells_count + 1);
            occurrences_map.set(mines, new_array);
            break :blk new_array;
        };
        for (0..group_maps.array.len) |group| {
            const mapvec = group_maps.at(group);
            const ind = counts.at(group);
            const v = mapvec.at(ind).?;
            const bit_count = v.at(edge_cells_count);

            for (0..edge_cells_count) |cell| {
                const b = v.at(cell) * (factor / bit_count);
                arr.array[cell] += b;
            }
        }
        arr.array[edge_cells_count] += factor;
        return;
    }

    var mapvec = group_maps.at(index);
    for (0..mapvec.array.len) |cnt| {
        if (mapvec.has(cnt)) {
            counts.set(index, @truncate(cnt));
            try backtrack_occurrences(index + 1, mines + @as(u16, @truncate(cnt)), group_maps, counts, occurrences_map);
        }
    }
}

fn calculate_probabilities(combinations: *map.mapvec64) !void {
    if (remain_mines - combinations.first() <= float_cells_count) {
        var v_ec: u16 = std.math.maxInt(u16);
        var v_fc: u16 = std.math.maxInt(u16);
        for (combinations.array, 0..) |array, m| {
            if (array) |_| {
                const min_ec = @min(remain_mines -% @as(u16, @truncate(m)), float_cells_count -% (remain_mines -% @as(u16, @truncate(m))));
                if (v_ec > min_ec) {
                    v_ec = min_ec;
                }
                const min_fc = @min(remain_mines -% @as(u16, @truncate(m)) -% 1, float_cells_count -% (remain_mines -% @as(u16, @truncate(m))));
                if (v_fc > min_fc) {
                    v_fc = min_fc;
                }
            }
        }

        var weights_map = try map.mapvecf64.new(combinations.array.len);
        defer weights_map.free();
        var weights_fc: f64 = 0.0;
        var weights_sum: f64 = 0.0;

        for (combinations.array, 0..) |array, m| {
            if (array) |arr| {
                const right: u16 = @min(remain_mines -% @as(u16, @truncate(m)), float_cells_count -% (remain_mines -% @as(u16, @truncate(m))));
                const len = right - v_ec;
                const left = float_cells_count + 1 - right;
                const weight = calc_weight(left, right, len);

                const right_fc: u16 = @min(remain_mines -% @as(u16, @truncate(m)) -% 1, float_cells_count -% (remain_mines -% @as(u16, @truncate(m))));
                const len_fc = right_fc - v_fc;
                const left_fc = float_cells_count - right_fc;
                const weight_fc = calc_weight(left_fc, right_fc, len_fc);

                weights_fc += weight_fc * @as(f64, @floatFromInt(arr.at(edge_cells_count)));
                weights_sum += weight * @as(f64, @floatFromInt(arr.at(edge_cells_count)));
                weights_map.set(m, weight);
            }
        }

        var fc_prob: f64 = weights_fc / weights_sum;
        if (v_ec > 0 or v_fc > 0) {
            if (v_ec == v_fc) {
                fc_prob *= (@as(f64, @floatFromInt(float_cells_count - v_fc)) / @as(f64, @floatFromInt(float_cells_count)));
            } else {
                fc_prob *= (@as(f64, @floatFromInt(v_ec)) / @as(f64, @floatFromInt(float_cells_count)));
            }
        }
        const fc_prob_code: u8 = @as(u8, @intFromFloat(@round(fc_prob * 100.0))) + 27;
        for (float_cells_list.array[0..float_cells_count]) |cell| {
            game_field.set(cell, fc_prob_code);
        }

        for (0..edge_cells_count) |cell| {
            var cell_weight: f64 = 0.0;
            for (combinations.array, 0..) |array, m| {
                if (array) |arr| {
                    cell_weight += @as(f64, @floatFromInt(arr.at(cell))) * weights_map.at(m);
                }
            }
            const code = @as(u8, @intFromFloat(@round(cell_weight / weights_sum * 100.0))) + 27;
            game_field.set(edge_cells_list.at(cell), code);
        }
    }
}

fn calc_weight(left: u16, right: u16, len: u16) f64 {
    var result: f64 = 1.0;
    if (right == std.math.maxInt(u16)) {
        return 0.0;
    } else if (right > 0) {
        for (0..len) |i| {
            result = result * @as(f64, @floatFromInt(left + i)) / @as(f64, @floatFromInt(right - i));
        }
    }
    return result;
}

pub fn probs_field() !vec.vec8 {
    @memcpy(game_field.array, input_field.array);

    edge_cells_list.clear();
    num_cells_list.clear();
    float_cells_list.clear();
    edge_cells_count = 0;
    float_cells_count = 0;

    try set_flags_and_float_cells();
    try set_safe_and_number_cells();
    try set_edge_cells();

    var groups = try vec.dvecpairdvec16_dvecpair16_8.new(8);
    defer groups.free();

    try get_cell_groups(&groups);

    if (groups.size == 0) {
        if (float_cells_count == 0) {
            if (check_if_27()) {
                return game_field;
            }
            game_field.set(0, 21);
            return game_field;
        } else {
            const float_prob: f64 = @as(f64, @floatFromInt(remain_mines)) / @as(f64, @floatFromInt(float_cells_count));
            const prob = @as(u8, @intFromFloat(@round(float_prob * 100.0))) + 27;
            for (float_cells_list.array[0..float_cells_list.size]) |cell| {
                game_field.set(cell, prob);
            }
            return game_field;
        }
    }

    var group_maps = try map.vecmapvec64.new(groups.size);
    defer group_maps.free();

    for (0..groups.size) |group| {
        const pair = groups.at(group);
        const edge_cells = pair.first;
        const num_cells = pair.second;

        if (edge_cells.size > 128) {
            game_field.set(0, 20);
            return game_field;
        }

        var combs = try map.mapvec64.new(edge_cells.size + 1);
        if (edge_cells.size <= LIMIT_BRUTE_FORCE) {
            try brute_force(&edge_cells, &num_cells, &combs);
        } else if (edge_cells.size <= 64) {
            try find_all_combinations64(&edge_cells, &num_cells, &combs);
        } else {
            try find_all_combinations128(&edge_cells, &num_cells, &combs);
        }
        group_maps.set(group, combs);
    }

    var occurrences_map = try map.mapvec64.new(edge_cells_count + 1);
    defer occurrences_map.free();
    try create_occurrences_map(&group_maps, &occurrences_map);

    if (occurrences_map.empty()) {
        game_field.set(0, 22);
        return game_field;
    }

    try calculate_probabilities(&occurrences_map);

    return game_field;
}
