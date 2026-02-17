const std = @import("std");
const stl = @import("stl");

const LIMIT_BRUTE_FORCE = 10;

const vector = struct {
    ptr: *anyopaque,
    size: usize,
    cap: usize,

    pub fn get_as_u64(self: *const vector) stl.vec.dvec64 {
        const ptr64: [*]u64 = @ptrCast(@alignCast(self.ptr));
        const slice = ptr64[0..self.cap];
        return stl.vec.dvec64{ .array = slice, .size = self.size };
    }

    pub fn put_as_u64(input: *const stl.vec.dvec64) vector {
        const ptr: *anyopaque = @ptrCast(@alignCast(input.array.ptr));
        return vector{ .ptr = ptr, .size = input.size, .cap = input.array.len };
    }

    pub fn get_as_u128(self: *const vector) stl.vec.dvec128 {
        const ptr128: [*]u128 = @ptrCast(@alignCast(self.ptr));
        const slice = ptr128[0..self.cap];
        return stl.vec.dvec128{ .array = slice, .size = self.size };
    }
    pub fn put_as_u128(input: *const stl.vec.dvec128) vector {
        const ptr: *anyopaque = @ptrCast(@alignCast(input.array.ptr));
        return vector{ .ptr = ptr, .size = input.size, .cap = input.array.len };
    }
};

const NumCellInfo = struct {
    combs: ?vector,
    low: u64,
    high: u64,
    constraints: stl.map.miniset16,
    mines: u8,
};

const NumTable = struct {
    table: []NumCellInfo,
    size: usize,

    pub fn init(size: usize) !NumTable {
        const tab = NumTable{
            .table = try stl.vec.allocator.alloc(NumCellInfo, size),
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

    pub fn set_constraints(self: *NumTable, num: u16, constraints: stl.map.miniset16) void {
        self.table[num].constraints = constraints;
    }

    pub fn set_combs64(self: *NumTable, num: u16, combs: stl.vec.dvec64) void {
        const c = self.table[num].combs;
        if (c != null) {
            const cc: stl.vec.dvec64 = c.?.get_as_u64();
            stl.vec.allocator.free(cc.array);
        }
        self.table[num].combs = vector.put_as_u64(&combs);
    }

    pub fn set_combs128(self: *NumTable, num: u16, combs: stl.vec.dvec128) void {
        const c = self.table[num].combs;
        if (c != null) {
            const cc: stl.vec.dvec64 = c.?.get_as_u64();
            stl.vec.allocator.free(cc.array);
        }
        self.table[num].combs = vector.put_as_u128(&combs);
    }

    pub fn get_combs64(self: *NumTable, num: u16) stl.vec.dvec64 {
        return self.table[num].combs.?.get_as_u64();
    }

    pub fn get_combs128(self: *NumTable, num: u16) stl.vec.dvec128 {
        return self.table[num].combs.?.get_as_u128();
    }

    pub fn get_constraints(self: *NumTable, num: u16) stl.map.miniset16 {
        return self.table[num].constraints;
    }

    pub fn get_mask_mines64(self: *NumTable, num: u16) stl.vec.pair64_8 {
        return stl.vec.pair64_8{
            .first = self.table[num].low,
            .second = self.table[num].mines,
        };
    }
    pub fn get_mask_mines128(self: *NumTable, num: u16) stl.vec.pair128_8 {
        return stl.vec.pair128_8{
            .first = @as(u128, self.table[num].low | @as(u128, self.table[num].high) << 64),
            .second = self.table[num].mines,
        };
    }

    pub fn deinit(self: *NumTable) void {
        var i: usize = 0;
        while (i < self.size) : (i += 1) {
            const c = self.table[i].combs;
            if (c != null) {
                const cc = c.?.get_as_u64();
                stl.vec.allocator.free(cc.array);
            }
        }
        stl.vec.allocator.free(self.table);
    }
};

pub const Probs = struct {
    input_field: stl.vec.vec8,
    game_field: stl.vec.vec8,
    temp_field: stl.vec.vec8,
    field_size: u16,
    real_size: u16,
    field_width: u8,
    field_height: u8,
    remain_mines: u16,
    total_mines: u16,
    last_number: u16,
    edge_cells_list: stl.vec.dvec16,
    edge_cells_count: u16,
    num_cells_list: stl.vec.dvecpair16_8,
    float_cells_list: stl.vec.dvec16,
    float_cells_count: u16,
    num_table: NumTable,
    neis_cache: stl.vec.vecneis,
    popcnts: [1 << LIMIT_BRUTE_FORCE]u8,

    pub fn init(w: u8, h: u8, m: u16) !Probs {
        var prob = Probs{
            .total_mines = m,
            .field_width = w,
            .field_height = h,
            .field_size = @as(u16, w) * h,
            .real_size = @as(u16, w) * h,
            .input_field = try stl.vec.vec8.new(@as(u16, w) * h),
            .game_field = try stl.vec.vec8.new(@as(u16, w) * h),
            .temp_field = try stl.vec.vec8.new(@as(u16, w) * h),
            .edge_cells_list = try stl.vec.dvec16.new(10),
            .edge_cells_count = 0,
            .num_cells_list = try stl.vec.dvecpair16_8.new(10),
            .float_cells_list = try stl.vec.dvec16.new(10),
            .float_cells_count = 0,
            .remain_mines = 0,
            .last_number = 0,
            .neis_cache = undefined,
            .popcnts = undefined,
            .num_table = undefined,
        };
        prob.fillpopcnts();
        prob.num_table = try NumTable.init(prob.field_size);
        try prob.set_neis_cache();

        return prob;
    }

    pub fn resize(self: *Probs, new_w: u8, new_h: u8, new_m: u16) !void {
        self.num_table.deinit();
        self.field_width = new_w;
        self.field_height = new_h;
        self.total_mines = new_m;
        self.field_size = @as(u16, new_w) * new_h;
        self.real_size = @as(u16, new_w) * new_h;
        try self.input_field.realloc(self.real_size);
        try self.game_field.realloc(self.real_size);
        try self.temp_field.realloc(self.real_size);
        self.num_table = try NumTable.init(self.field_size);

        self.neis_cache.free();
        try self.set_neis_cache();
    }

    pub fn deinit(self: *Probs) void {
        self.input_field.free();
        self.game_field.free();
        self.temp_field.free();
        self.edge_cells_list.free();
        self.num_cells_list.free();
        self.float_cells_list.free();
        self.num_table.deinit();
    }

    pub fn get_input_ptr(self: *Probs) [*]u8 {
        return self.input_field.array.ptr;
    }
    pub fn get_input_len(self: *Probs) usize {
        return self.input_field.array.len;
    }

    pub fn get_probs_ptr(self: *Probs) [*]u8 {
        return self.game_field.array.ptr;
    }
    pub fn get_probs_len(self: *Probs) usize {
        return self.game_field.array.len;
    }

    fn set_neis_cache(self: *Probs) !void {
        self.neis_cache = try stl.vec.vecneis.new(self.field_size);
        const fw = self.field_width;
        var c: u16 = 0;
        while (c < self.field_size) : (c += 1) {
            const row = c / fw;
            const col = c % fw;

            if (row == 0) {
                if (col == 0) {
                    self.neis_cache.add3(1, fw, fw + 1);
                } else if (col == fw - 1) {
                    self.neis_cache.add3(c - 1, c + fw - 1, c + fw);
                } else {
                    self.neis_cache.add5(c - 1, c + 1, c + fw - 1, c + fw, c + 1 + fw);
                }
            } else if (row == self.field_height - 1) {
                if (col == 0) {
                    self.neis_cache.add3(c - fw, c + 1 - fw, c + 1);
                } else if (col == fw - 1) {
                    self.neis_cache.add3(c - 1, c - 1 - fw, c - fw);
                } else {
                    self.neis_cache.add5(c - 1, c + 1, c + 1 - fw, c - 1 - fw, c - fw);
                }
            } else {
                if (col == 0) {
                    self.neis_cache.add5(c - fw, c + 1 - fw, c + 1, c + fw, c + fw + 1);
                } else if (col == fw - 1) {
                    self.neis_cache.add5(c - 1 - fw, c - fw, c - 1, c - 1 + fw, c + fw);
                } else {
                    self.neis_cache.add8(c - 1 - fw, c - fw, c + 1 - fw, c - 1, c + 1, c - 1 + fw, c + fw, c + fw + 1);
                }
            }
        }
    }
    fn fillpopcnts(self: *Probs) void {
        self.popcnts[0] = 0;
        var i: usize = 0;
        const limit = 1 << LIMIT_BRUTE_FORCE;
        while (i < limit) : (i += 1) {
            const last: u8 = @truncate(i);
            self.popcnts[i] = (last & 1) + self.popcnts[i >> 1];
        }
    }
    fn get_neis(self: *Probs, c: u16) stl.vec.neis {
        return self.neis_cache.at(c);
    }
    fn set_flags_and_float_cells(self: *Probs) !void {
        self.temp_field.fill(26);
        const f = self.game_field.array;
        var i: usize = 0;
        while (i < self.field_size) : (i += 1) {
            const gameval = self.game_field.at(i);
            const neighbors = self.get_neis(@truncate(i));
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
                try self.float_cells_list.add(@truncate(i));
                self.temp_field.set(i, 26);
            } else if (gameval > 0 and gameval < 9 and gameval == closed_count) {
                switch (neighbors.size) {
                    8 => {
                        @branchHint(.likely);
                        if (f[n[0]] == 9) {
                            self.temp_field.set(n[0], 11);
                        } else {
                            self.temp_field.set(n[0], f[n[0]]);
                        }
                        if (f[n[1]] == 9) {
                            self.temp_field.set(n[1], 11);
                        } else {
                            self.temp_field.set(n[1], f[n[1]]);
                        }
                        if (f[n[2]] == 9) {
                            self.temp_field.set(n[2], 11);
                        } else {
                            self.temp_field.set(n[2], f[n[2]]);
                        }
                        if (f[n[3]] == 9) {
                            self.temp_field.set(n[3], 11);
                        } else {
                            self.temp_field.set(n[3], f[n[3]]);
                        }
                        if (f[n[4]] == 9) {
                            self.temp_field.set(n[4], 11);
                        } else {
                            self.temp_field.set(n[4], f[n[4]]);
                        }
                        if (f[n[5]] == 9) {
                            self.temp_field.set(n[5], 11);
                        } else {
                            self.temp_field.set(n[5], f[n[5]]);
                        }
                        if (f[n[6]] == 9) {
                            self.temp_field.set(n[6], 11);
                        } else {
                            self.temp_field.set(n[6], f[n[6]]);
                        }
                        if (f[n[7]] == 9) {
                            self.temp_field.set(n[7], 11);
                        } else {
                            self.temp_field.set(n[7], f[n[7]]);
                        }
                    },
                    5 => {
                        if (f[n[0]] == 9) {
                            self.temp_field.set(n[0], 11);
                        } else {
                            self.temp_field.set(n[0], f[n[0]]);
                        }
                        if (f[n[1]] == 9) {
                            self.temp_field.set(n[1], 11);
                        } else {
                            self.temp_field.set(n[1], f[n[1]]);
                        }
                        if (f[n[2]] == 9) {
                            self.temp_field.set(n[2], 11);
                        } else {
                            self.temp_field.set(n[2], f[n[2]]);
                        }
                        if (f[n[3]] == 9) {
                            self.temp_field.set(n[3], 11);
                        } else {
                            self.temp_field.set(n[3], f[n[3]]);
                        }
                        if (f[n[4]] == 9) {
                            self.temp_field.set(n[4], 11);
                        } else {
                            self.temp_field.set(n[4], f[n[4]]);
                        }
                    },
                    3 => {
                        if (f[n[0]] == 9) {
                            self.temp_field.set(n[0], 11);
                        } else {
                            self.temp_field.set(n[0], f[n[0]]);
                        }
                        if (f[n[1]] == 9) {
                            self.temp_field.set(n[1], 11);
                        } else {
                            self.temp_field.set(n[1], f[n[1]]);
                        }
                        if (f[n[2]] == 9) {
                            self.temp_field.set(n[2], 11);
                        } else {
                            self.temp_field.set(n[2], f[n[2]]);
                        }
                    },
                    else => {
                        unreachable;
                    },
                }
                self.temp_field.set(i, gameval);
            } else if (self.temp_field.at(i) != 11) {
                self.temp_field.set(i, gameval);
            }
        }
        @memcpy(self.game_field.array, self.temp_field.array);
        self.float_cells_count = @truncate(self.float_cells_list.size);
    }
    fn set_safe_and_number_cells(self: *Probs) !void {
        var flag_count: u16 = 0;
        const f = self.game_field.array;
        var i: usize = 0;
        while (i < self.field_size) : (i += 1) {
            const gameval = self.game_field.at(i);
            if (gameval < 9) {
                const neighbors = self.get_neis(@truncate(i));
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
                            if (f[n[0]] == 9) self.temp_field.set(n[0], 27);
                            if (f[n[1]] == 9) self.temp_field.set(n[1], 27);
                            if (f[n[2]] == 9) self.temp_field.set(n[2], 27);
                            if (f[n[3]] == 9) self.temp_field.set(n[3], 27);
                            if (f[n[4]] == 9) self.temp_field.set(n[4], 27);
                            if (f[n[5]] == 9) self.temp_field.set(n[5], 27);
                            if (f[n[6]] == 9) self.temp_field.set(n[6], 27);
                            if (f[n[7]] == 9) self.temp_field.set(n[7], 27);
                        } else {
                            try self.num_cells_list.add(stl.vec.pair16_8{ .first = @truncate(i), .second = (gameval - flags_count) });
                        }
                    },
                    5 => {
                        flags_count = @as(u8, @intFromBool(f[n[0]] == 11)) + @as(u8, @intFromBool(f[n[1]] == 11)) +
                            @as(u8, @intFromBool(f[n[2]] == 11)) + @as(u8, @intFromBool(f[n[3]] == 11)) +
                            @as(u8, @intFromBool(f[n[4]] == 11));
                        if (gameval == flags_count) {
                            if (f[n[0]] == 9) self.temp_field.set(n[0], 27);
                            if (f[n[1]] == 9) self.temp_field.set(n[1], 27);
                            if (f[n[2]] == 9) self.temp_field.set(n[2], 27);
                            if (f[n[3]] == 9) self.temp_field.set(n[3], 27);
                            if (f[n[4]] == 9) self.temp_field.set(n[4], 27);
                        } else {
                            try self.num_cells_list.add(stl.vec.pair16_8{ .first = @truncate(i), .second = (gameval - flags_count) });
                        }
                    },
                    3 => {
                        flags_count = @as(u8, @intFromBool(f[n[0]] == 11)) + @as(u8, @intFromBool(f[n[1]] == 11)) +
                            @as(u8, @intFromBool(f[n[2]] == 11));
                        if (gameval == flags_count) {
                            if (f[n[0]] == 9) self.temp_field.set(n[0], 27);
                            if (f[n[1]] == 9) self.temp_field.set(n[1], 27);
                            if (f[n[2]] == 9) self.temp_field.set(n[2], 27);
                        } else {
                            try self.num_cells_list.add(stl.vec.pair16_8{ .first = @truncate(i), .second = (gameval - flags_count) });
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
        @memcpy(self.game_field.array[0..self.field_size], self.temp_field.array[0..self.field_size]);
        self.remain_mines = self.total_mines - flag_count;
    }
    fn set_edge_cells(self: *Probs) !void {
        var i: u16 = 0;
        while (i < self.field_size) : (i += 1) {
            const gval = self.game_field.at(i);
            if (gval == 9) {
                try self.edge_cells_list.add(i);
            }
        }
        self.edge_cells_count = @truncate(self.edge_cells_list.size);
    }
    fn check_if_27(self: *Probs) bool {
        var i: usize = 0;
        const p27: @Vector(16, u8) = @splat(27);
        while (i < self.real_size) : (i += 16) {
            const data: @Vector(16, u8) = self.game_field.array[i..][0..16].*;
            const eq = data == p27;
            const mask: u16 = @bitCast(eq);
            if (mask > 0) {
                return true;
            }
        }
        return false;
    }
    fn cell_to_bit(self: *Probs, key: u16) u7 {
        const value = self.temp_field.at(key);
        return if (value != std.math.maxInt(u8)) @truncate(value) else 127;
    }
    fn get_cell_groups(self: *Probs, groups: *stl.vec.dvecpairdvec16_dvecpair16_8) !void {
        var checked_count: u16 = 0;

        while (checked_count < self.edge_cells_count) {
            var first_cell = self.edge_cells_list.at(0);

            if (groups.size != 0) {
                var i: usize = 0;
                while (i < self.edge_cells_count) : (i += 1) {
                    var skip = false;
                    var g: usize = 0;
                    outer: while (g < groups.size) : (g += 1) {
                        const groupsgfirst = groups.at(g).first;
                        var edgecell: usize = 0;
                        while (edgecell < groupsgfirst.size) : (edgecell += 1) {
                            if (groupsgfirst.at(edgecell) == self.edge_cells_list.at(i)) {
                                skip = true;
                                break :outer;
                            }
                        }
                    }
                    if (!skip) {
                        first_cell = self.edge_cells_list.at(i);
                        break;
                    }
                }
            }

            var edge_cells = try stl.vec.dvec16.new(8);
            try edge_cells.add(first_cell);
            var num_cells = try stl.vec.dvec16.new(8);
            defer num_cells.free();
            try self.make_cell_group(&edge_cells, &num_cells);

            var num_cells_with_counts = try stl.vec.dvecpair16_8.new(self.num_cells_list.size);
            var n: usize = 0;
            while (n < num_cells.size) : (n += 1) {
                var num: usize = 0;
                while (num < self.num_cells_list.size) : (num += 1) {
                    if (num_cells.at(n) == self.num_cells_list.at(num).first) {
                        try num_cells_with_counts.ins(n, self.num_cells_list.at(num));
                        break;
                    }
                }
            }

            checked_count += @truncate(edge_cells.size);
            std.sort.block(u16, edge_cells.array[0..edge_cells.size], {}, std.sort.asc(u16));
            try groups.add(edge_cells, num_cells_with_counts);
        }
    }
    fn make_cell_group(self: *Probs, edge_cells: *stl.vec.dvec16, num_cells: *stl.vec.dvec16) !void {
        var edges_checked: usize = 0;
        var nums_checked: usize = 0;
        while (true) {
            var i: usize = edges_checked;
            while (i < edge_cells.size) : (i += 1) {
                const neighbors = self.get_neis(edge_cells.at(i));
                var j: usize = 0;
                while (j < neighbors.size) : (j += 1) {
                    const nei_index = neighbors.at(j);
                    if (self.game_field.at(nei_index) < 9 and !num_cells.has(nei_index)) {
                        try num_cells.add(nei_index);
                    }
                }
                edges_checked += 1;
            }

            i = nums_checked;
            while (i < num_cells.size) : (i += 1) {
                const neighbors = self.get_neis(num_cells.at(i));
                var j: usize = 0;
                while (j < neighbors.size) : (j += 1) {
                    const nei_index = neighbors.at(j);
                    if (self.game_field.at(nei_index) == 9 and !edge_cells.has(nei_index)) {
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
        var i: usize = 0;
        while (i < edge_size) : (i += 1) {
            if (edge_cells[i] == edge) {
                return @truncate(i);
            }
        }
        return 31;
    }

    fn brute_force(self: *Probs, edge_cells: *const stl.vec.dvec16, num_cells: *const stl.vec.dvecpair16_8, combs: *stl.map.mapvec64) !void {
        const edge_size = edge_cells.size;
        var num_size = num_cells.size;
        var mapping: [LIMIT_BRUTE_FORCE]u8 = undefined;

        var i: u8 = 0;
        while (i < edge_size) : (i += 1) {
            const cell = edge_cells.at(i);
            mapping[i] = edge_index(cell, self.edge_cells_list.array.ptr, self.edge_cells_count);
        }
        var seen_masks: [2 * LIMIT_BRUTE_FORCE]u16 = undefined;
        var temp_size: usize = 0;

        var border_info: [2 * LIMIT_BRUTE_FORCE]stl.vec.pair16_8 = undefined;

        i = 0;
        while (i < num_size) : (i += 1) {
            const num = num_cells.at(i);
            const num_index = num.first;
            const mine_count = num.second;
            const neighbors = self.get_neis(num_index);
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
            var s: usize = 0;
            while (s < temp_size) : (s += 1) {
                if (seen_masks[s] == mask) {
                    contains = true;
                    break;
                }
            }

            if (!contains) {
                seen_masks[temp_size] = mask;
                border_info[temp_size] = stl.vec.pair16_8{ .first = mask, .second = mine_count };
                temp_size += 1;
            }
        }
        num_size = temp_size;
        var count_to_index: [LIMIT_BRUTE_FORCE]u8 = undefined;
        @memset(&count_to_index, std.math.maxInt(u8));
        var result: [5]stl.vec.vec64 = undefined;
        var result_size: usize = 0;

        const limit: u16 = (@as(u16, 1) << @as(u4, @truncate(edge_size))) - 1;
        var mask: u16 = 0;
        while (mask <= limit) : (mask += 1) {
            var valid = true;
            const bits = self.popcnts[mask];
            i = 0;
            while (i < num_size) : (i += 1) {
                const mask_mines = border_info[i];
                const overlap = mask & mask_mines.first;
                if (self.popcnts[overlap] != mask_mines.second) {
                    valid = false;
                    break;
                }
            }
            if (valid and bits <= self.remain_mines) {
                if (count_to_index[bits] == std.math.maxInt(u8)) {
                    count_to_index[bits] = @truncate(result_size);
                    const v = try stl.vec.vec64.new(self.edge_cells_count + 1);
                    result[result_size] = v;
                    result_size += 1;
                }
                const ind = count_to_index[bits];
                var c = result[ind];
                var maskcpy = mask;
                while (maskcpy > 0) {
                    const t: u16 = @ctz(maskcpy);
                    maskcpy &= maskcpy - 1;
                    const ind2 = mapping[t];
                    c.array[ind2] += 1;
                }
                c.array[self.edge_cells_count] += 1;
            }
        }

        var bit_count: u8 = 0;
        while (bit_count < LIMIT_BRUTE_FORCE) : (bit_count += 1) {
            const index = count_to_index[bit_count];
            if (index != std.math.maxInt(u8)) {
                const val = result[index];
                combs.set(bit_count, val);
            }
        }
    }

    fn find_all_combinations64(self: *Probs, edge_cells: *const stl.vec.dvec16, num_cells: *const stl.vec.dvecpair16_8, combs: *stl.map.mapvec64) !void {
        const edge_size = edge_cells.size;
        var num_size = num_cells.size;
        var mapping = try stl.vec.vec8.new(edge_size);
        defer mapping.free();
        @memset(self.temp_field.array, std.math.maxInt(u8));

        var i: usize = 0;
        while (i < edge_size) : (i += 1) {
            const cell = edge_cells.at(i);
            const ind = std.sort.binarySearch(u16, self.edge_cells_list.array[0..self.edge_cells_list.size], cell, stl.map.set16.u16Order).?;
            mapping.set(i, @truncate(ind));
            self.temp_field.set(cell, @truncate(i));
        }

        var seen_masks = try stl.map.set64.new(num_size);
        defer seen_masks.free();
        var num_set = try stl.map.set16.new(num_size);
        defer num_set.free();

        i = 0;
        while (i < num_size) : (i += 1) {
            const num = num_cells.at(i);
            const cell_index = num.first;
            const mine_count = num.second;
            const neighbors = self.get_neis(cell_index);
            var mask0: u128 = 0;

            switch (neighbors.size) {
                8 => {
                    mask0 |= (@as(u128, 1) << self.cell_to_bit(neighbors.at(0))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(1))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(2))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(3))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(4))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(5))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(6))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(7)));
                },
                5 => {
                    mask0 |= (@as(u128, 1) << self.cell_to_bit(neighbors.at(0))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(1))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(2))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(3))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(4)));
                },
                3 => {
                    mask0 |= (@as(u128, 1) << self.cell_to_bit(neighbors.at(0))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(1))) |
                        (@as(u128, 1) << self.cell_to_bit(neighbors.at(2)));
                },
                else => unreachable,
            }
            const mask: u64 = @truncate(mask0);

            if (!seen_masks.has(mask)) {
                try seen_masks.ins(mask);
                try num_set.ins(cell_index);
                var combos = try stl.vec.dvec64.new(10);
                try bit_combs64(mask, mine_count, &combos);
                self.num_table.set_combs64(cell_index, combos);
                self.num_table.set_mask_mines64(cell_index, mask, @as(u8, @popCount(mask)) - mine_count);
            }
        }
        num_size = num_set.size;

        var edges_neis = try stl.vec.vecneis.new(edge_size);
        defer edges_neis.free();
        i = 0;
        while (i < edge_size) : (i += 1) {
            const edge = edge_cells.at(i);
            const neighbors = self.get_neis(edge);
            var edge_neis: stl.vec.neis = undefined;
            edge_neis.size = 0;
            var j: usize = 0;
            while (j < neighbors.size) : (j += 1) {
                const nei = neighbors.at(j);
                if (num_set.has(nei)) {
                    edge_neis.add(nei);
                }
            }
            edges_neis.add(edge_neis);
        }

        i = 0;
        while (i < num_size) : (i += 1) {
            const num = num_set.at(i);
            const num_neighbors = self.get_neis(num);
            var constraints: stl.map.miniset16 = undefined;
            constraints.size = 0;
            var j: usize = 0;
            while (j < num_neighbors.size) : (j += 1) {
                const nei = num_neighbors.at(j);
                const index = edge_cells.index_of(nei);
                if (index != std.math.maxInt(usize)) {
                    const edges = edges_neis.at(index);
                    var k: usize = 0;
                    while (k < edges.size) : (k += 1) {
                        const edge = edges.at(k);
                        constraints.ins(edge);
                    }
                }
            }
            self.num_table.set_constraints(num, constraints);
        }

        const num_vec: stl.vec.vec16 = stl.vec.vec16{ .array = num_set.array };

        var count_to_index = try stl.vec.vec8.new(edge_size + 1);
        defer count_to_index.free();
        count_to_index.fill(std.math.maxInt(u8));
        var result = try stl.vec.dvecvec64.new(5);
        defer stl.vec.allocator.free(result.array);

        self.last_number = num_vec.at(num_size - 1);
        try self.mine_combinations64(num_vec.at(0), 0, &num_vec, &count_to_index, &result, &mapping);

        var bit_count: usize = 0;
        while (bit_count < edge_size) : (bit_count += 1) {
            const index = count_to_index.at(bit_count);
            if (index != std.math.maxInt(u8)) {
                const val = result.at(index);
                combs.set(bit_count, val);
            }
        }
    }
    fn bit_combs64(full_mask: u64, k: u8, result: *stl.vec.dvec64) !void {
        var bit_pos: [64]u8 = undefined;
        var bit_size: usize = 0;
        var i: u8 = 0;
        while (i < 64) : (i += 1) {
            if (full_mask & (@as(u64, 1) << @as(u6, @truncate(i))) > 0) {
                bit_pos[bit_size] = i;
                bit_size += 1;
            }
        }
        const total: u8 = @truncate(bit_size);
        if (k > total) {
            return;
        }
        var selection = try stl.vec.vecbool.new(total, k);
        defer selection.free();

        while (true) {
            var mask: u64 = 0;
            var j: usize = 0;
            while (j < total) : (j += 1) {
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
    fn mine_combinations64(self: *Probs, current_number: u16, mask: u64, num_set: *const stl.vec.vec16, count_to_index: *stl.vec.vec8, result: *stl.vec.dvecvec64, mapping: *const stl.vec.vec8) !void {
        const constraints = self.num_table.get_constraints(current_number);
        const combs = self.num_table.get_combs64(current_number);

        var i: usize = 0;
        while (i < combs.size) : (i += 1) {
            const combo = combs.at(i);
            const new_mask = mask | combo;
            var valid = true;

            var j: usize = 0;
            while (j < constraints.size) : (j += 1) {
                const constraint = constraints.at(j);
                const mask_mine = self.num_table.get_mask_mines64(constraint);
                const constraint_mask = mask_mine.first;
                const mines = mask_mine.second;
                const different_bits: u8 = @popCount((new_mask ^ constraint_mask) & constraint_mask);

                if (different_bits < mines) {
                    valid = false;
                    break;
                }
            }

            if (valid) {
                if (current_number != self.last_number) {
                    const next_number = num_set.next(current_number);
                    try self.mine_combinations64(next_number, new_mask, num_set, count_to_index, result, mapping);
                } else {
                    const bit_count: u8 = @popCount(new_mask);
                    if (bit_count <= self.remain_mines) {
                        try self.add_combination64(new_mask, bit_count, count_to_index, result, mapping);
                    }
                }
            }
        }
    }
    fn add_combination64(self: *Probs, mask: u64, bit_count: u8, count_to_index: *stl.vec.vec8, result: *stl.vec.dvecvec64, mapping: *const stl.vec.vec8) !void {
        if (count_to_index.at(bit_count) == std.math.maxInt(u8)) {
            count_to_index.set(bit_count, @truncate(result.size));
            const v = try stl.vec.vec64.new(self.edge_cells_count + 1);
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
        c.array[self.edge_cells_count] += 1;
    }

    fn find_all_combinations128(self: *Probs, edge_cells: *const stl.vec.dvec16, num_cells: *const stl.vec.dvecpair16_8, combs: *stl.map.mapvec64) !void {
        const edge_size = edge_cells.size;
        var num_size = num_cells.size;
        var mapping = try stl.vec.vec8.new(edge_size);
        defer mapping.free();
        @memset(self.temp_field.array, std.math.maxInt(u8));

        var i: usize = 0;
        while (i < edge_size) : (i += 1) {
            const cell = edge_cells.at(i);
            const ind = std.sort.binarySearch(u16, self.edge_cells_list.array[0..self.edge_cells_list.size], cell, stl.map.set16.u16Order).?;
            mapping.set(i, @truncate(ind));
            self.temp_field.set(cell, @truncate(i));
        }

        var seen_masks = try stl.map.set128.new(num_size);
        defer seen_masks.free();
        var num_set = try stl.map.set16.new(num_size);
        defer num_set.free();

        i = 0;
        while (i < num_size) : (i += 1) {
            const num = num_cells.at(i);
            const cell_index = num.first;
            const mine_count = num.second;
            const neighbors = self.get_neis(cell_index);
            var mask: u128 = 0;

            var j: usize = 0;
            while (j < neighbors.size) : (j += 1) {
                const nei_index = neighbors.at(j);
                const val = self.cell_to_bit(nei_index);
                if (val != 127) {
                    mask |= (@as(u128, 1) << val);
                }
            }

            if (!seen_masks.has(mask)) {
                try seen_masks.ins(mask);
                try num_set.ins(cell_index);
                var combos = try stl.vec.dvec128.new(10);
                try bit_combs128(mask, mine_count, &combos);
                self.num_table.set_combs128(cell_index, combos);
                self.num_table.set_mask_mines128(cell_index, mask, @as(u8, @popCount(mask)) - mine_count);
            }
        }
        num_size = num_set.size;

        var edges_neis = try stl.vec.vecneis.new(edge_size);
        defer edges_neis.free();
        i = 0;
        while (i < edge_size) : (i += 1) {
            const edge = edge_cells.at(i);
            const neighbors = self.get_neis(edge);
            var edge_neis: stl.vec.neis = undefined;
            edge_neis.size = 0;
            var j: usize = 0;
            while (j < neighbors.size) : (j += 1) {
                const nei = neighbors.at(j);
                if (num_set.has(nei)) {
                    edge_neis.add(nei);
                }
            }
            edges_neis.add(edge_neis);
        }

        i = 0;
        while (i < num_size) : (i += 1) {
            const num = num_set.at(i);
            const num_neighbors = self.get_neis(num);
            var constraints: stl.map.miniset16 = undefined;
            constraints.size = 0;
            var j: usize = 0;
            while (j < num_neighbors.size) : (j += 1) {
                const nei = num_neighbors.at(j);
                const index = edge_cells.index_of(nei);
                if (index != std.math.maxInt(usize)) {
                    const edges = edges_neis.at(index);
                    var k: usize = 0;
                    while (k < edges.size) : (k += 1) {
                        const edge = edges.at(k);
                        constraints.ins(edge);
                    }
                }
            }
            self.num_table.set_constraints(num, constraints);
        }

        const num_vec: stl.vec.vec16 = stl.vec.vec16{ .array = num_set.array };

        var count_to_index = try stl.vec.vec8.new(edge_size + 1);
        defer count_to_index.free();
        count_to_index.fill(std.math.maxInt(u8));
        var result = try stl.vec.dvecvec64.new(5);
        defer stl.vec.allocator.free(result.array);

        self.last_number = num_vec.at(num_size - 1);
        try self.mine_combinations128(num_vec.at(0), 0, &num_vec, &count_to_index, &result, &mapping);

        var bit_count: usize = 0;
        while (bit_count < edge_size) : (bit_count += 1) {
            const index = count_to_index.at(bit_count);
            if (index != std.math.maxInt(u8)) {
                const val = result.at(index);
                combs.set(bit_count, val);
            }
        }
    }
    fn bit_combs128(full_mask: u128, k: u8, result: *stl.vec.dvec128) !void {
        var bit_pos: [128]u8 = undefined;
        var bit_size: usize = 0;
        var i: u8 = 0;
        while (i < 128) : (i += 1) {
            if (full_mask & (@as(u128, 1) << @as(u7, @truncate(i))) > 0) {
                bit_pos[bit_size] = i;
                bit_size += 1;
            }
        }
        const total: u8 = @truncate(bit_size);
        if (k > total) {
            return;
        }
        var selection = try stl.vec.vecbool.new(total, k);
        defer selection.free();

        while (true) {
            var mask: u128 = 0;
            var j: usize = 0;
            while (j < total) : (j += 1) {
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
    fn mine_combinations128(self: *Probs, current_number: u16, mask: u128, num_set: *const stl.vec.vec16, count_to_index: *stl.vec.vec8, result: *stl.vec.dvecvec64, mapping: *const stl.vec.vec8) !void {
        const constraints = self.num_table.get_constraints(current_number);
        const combs = self.num_table.get_combs128(current_number);

        var i: usize = 0;
        while (i < combs.size) : (i += 1) {
            const combo = combs.at(i);
            const new_mask = mask | combo;
            var valid = true;

            var j: usize = 0;
            while (j < constraints.size) : (j += 1) {
                const constraint = constraints.at(j);
                const mask_mine = self.num_table.get_mask_mines128(constraint);
                const constraint_mask = mask_mine.first;
                const mines = mask_mine.second;
                const different_bits: u8 = @popCount((new_mask ^ constraint_mask) & constraint_mask);

                if (different_bits < mines) {
                    valid = false;
                    break;
                }
            }

            if (valid) {
                if (current_number != self.last_number) {
                    const next_number = num_set.next(current_number);
                    try self.mine_combinations128(next_number, new_mask, num_set, count_to_index, result, mapping);
                } else {
                    const bit_count: u8 = @popCount(new_mask);
                    if (bit_count <= self.remain_mines) {
                        try self.add_combination128(new_mask, bit_count, count_to_index, result, mapping);
                    }
                }
            }
        }
    }
    fn add_combination128(self: *Probs, mask: u128, bit_count: u8, count_to_index: *stl.vec.vec8, result: *stl.vec.dvecvec64, mapping: *const stl.vec.vec8) !void {
        if (count_to_index.at(bit_count) == std.math.maxInt(u8)) {
            count_to_index.set(bit_count, @truncate(result.size));
            const v = try stl.vec.vec64.new(self.edge_cells_count + 1);
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
        c.array[self.edge_cells_count] += 1;
    }

    fn create_occurrences_map(self: *Probs, group_maps: *stl.map.vecmapvec64, occurrences_map: *stl.map.mapvec64) !void {
        var counts = try stl.vec.vec8.new(group_maps.array.len);
        defer counts.free();
        counts.fill(0);
        try self.backtrack_occurrences(0, 0, group_maps, &counts, occurrences_map);
    }
    fn backtrack_occurrences(self: *Probs, index: usize, mines: u16, group_maps: *stl.map.vecmapvec64, counts: *stl.vec.vec8, occurrences_map: *stl.map.mapvec64) !void {
        if (mines > self.remain_mines) {
            return;
        }

        if (index == group_maps.array.len) {
            if (self.remain_mines - mines > self.float_cells_count) {
                return;
            }
            var factor: u64 = 1;
            var group: usize = 0;
            while (group < group_maps.array.len) : (group += 1) {
                const map = group_maps.at(group);
                const ind = counts.at(group);
                const v = map.at(ind).?;
                const val = v.at(self.edge_cells_count);
                factor *= val;
            }
            var arr: stl.vec.vec64 = occurrences_map.at(mines) orelse blk: {
                const new_array = try stl.vec.vec64.new(self.edge_cells_count + 1);
                occurrences_map.set(mines, new_array);
                break :blk new_array;
            };
            group = 0;
            while (group < group_maps.array.len) : (group += 1) {
                const map = group_maps.at(group);
                const ind = counts.at(group);
                const v = map.at(ind).?;
                const bit_count = v.at(self.edge_cells_count);

                var cell: u16 = 0;
                while (cell < self.edge_cells_count) : (cell += 1) {
                    const b = v.at(cell) * (factor / bit_count);
                    arr.array[cell] += b;
                }
            }
            arr.array[self.edge_cells_count] += factor;
            return;
        }

        var map = group_maps.at(index);
        var cnt: u8 = 0;
        while (cnt < map.array.len) : (cnt += 1) {
            if (map.has(cnt)) {
                counts.set(index, cnt);
                try self.backtrack_occurrences(index + 1, mines + cnt, group_maps, counts, occurrences_map);
            }
        }
    }

    fn calculate_probabilities(self: *Probs, combinations: *stl.map.mapvec64) !void {
        if (self.remain_mines - combinations.first() <= self.float_cells_count) {
            var v_ec: u16 = std.math.maxInt(u16);
            var v_fc: u16 = std.math.maxInt(u16);
            var m: u16 = 0;
            while (m < combinations.array.len) : (m += 1) {
                const arr = combinations.at(m);
                if (arr != null) {
                    const min_ec = @min(self.remain_mines -% m, self.float_cells_count -% (self.remain_mines -% m));
                    if (v_ec > min_ec) {
                        v_ec = min_ec;
                    }
                    const min_fc = @min(self.remain_mines -% m -% 1, self.float_cells_count -% (self.remain_mines -% m));
                    if (v_fc > min_fc) {
                        v_fc = min_fc;
                    }
                }
            }

            var weights_map = try stl.map.mapvecf64.new(combinations.array.len);
            defer weights_map.free();
            var weights_fc: f64 = 0.0;
            var weights_sum: f64 = 0.0;

            m = 0;
            while (m < combinations.array.len) : (m += 1) {
                const array = combinations.at(m);
                if (array != null) {
                    const arr = array.?;
                    const right: u16 = @min(self.remain_mines -% m, self.float_cells_count -% (self.remain_mines -% m));
                    const len = right - v_ec;
                    const left = self.float_cells_count + 1 - right;
                    const weight = calc_weight(left, right, len);

                    const right_fc: u16 = @min(self.remain_mines -% m -% 1, self.float_cells_count -% (self.remain_mines -% m));
                    const len_fc = right_fc - v_fc;
                    const left_fc = self.float_cells_count - right_fc;
                    const weight_fc = calc_weight(left_fc, right_fc, len_fc);

                    weights_fc += weight_fc * @as(f64, @floatFromInt(arr.at(self.edge_cells_count)));
                    weights_sum += weight * @as(f64, @floatFromInt(arr.at(self.edge_cells_count)));
                    weights_map.set(m, weight);
                }
            }

            var fc_prob: f64 = weights_fc / weights_sum;
            if (v_ec > 0 or v_fc > 0) {
                if (v_ec == v_fc) {
                    fc_prob *= (@as(f64, @floatFromInt(self.float_cells_count - v_fc)) / @as(f64, @floatFromInt(self.float_cells_count)));
                } else {
                    fc_prob *= (@as(f64, @floatFromInt(v_ec)) / @as(f64, @floatFromInt(self.float_cells_count)));
                }
            }
            const fc_prob_code: u8 = @as(u8, @intFromFloat(@round(fc_prob * 100.0))) + 27;
            var i: u16 = 0;
            while (i < self.float_cells_count) : (i += 1) {
                const cell = self.float_cells_list.at(i);
                self.game_field.set(cell, fc_prob_code);
            }

            var cell: u16 = 0;
            while (cell < self.edge_cells_count) : (cell += 1) {
                var cell_weight: f64 = 0.0;
                m = 0;
                while (m < combinations.array.len) : (m += 1) {
                    const array = combinations.at(m);
                    if (array != null) {
                        const arr = array.?;
                        cell_weight += @as(f64, @floatFromInt(arr.at(cell))) * weights_map.at(m);
                    }
                }
                const code = @as(u8, @intFromFloat(@round(cell_weight / weights_sum * 100.0))) + 27;
                self.game_field.set(self.edge_cells_list.at(cell), code);
            }
        }
    }
    fn calc_weight(left: u16, right: u16, len: u16) f64 {
        var result: f64 = 1.0;
        if (right == std.math.maxInt(u16)) {
            return 0.0;
        } else if (right > 0) {
            var i: u16 = 0;
            while (i < len) : (i += 1) {
                result = result * @as(f64, @floatFromInt(left + i)) / @as(f64, @floatFromInt(right - i));
            }
        }
        return result;
    }

    pub fn probs_field(self: *Probs) !stl.vec.vec8 {
        @memcpy(self.game_field.array, self.input_field.array);

        self.edge_cells_list.clear();
        self.num_cells_list.clear();
        self.float_cells_list.clear();
        self.edge_cells_count = 0;
        self.float_cells_count = 0;

        try self.set_flags_and_float_cells();
        try self.set_safe_and_number_cells();
        try self.set_edge_cells();

        var groups = try stl.vec.dvecpairdvec16_dvecpair16_8.new(8);
        defer groups.free();

        try self.get_cell_groups(&groups);

        if (groups.size == 0) {
            if (self.float_cells_count == 0) {
                if (self.check_if_27()) {
                    return self.game_field;
                }
                self.game_field.set(0, 21);
                return self.game_field;
            } else {
                const float_prob: f64 = @as(f64, @floatFromInt(self.remain_mines)) / @as(f64, @floatFromInt(self.float_cells_count));
                const prob = @as(u8, @intFromFloat(@round(float_prob * 100.0))) + 27;
                var i: usize = 0;
                while (i < self.float_cells_list.size) : (i += 1) {
                    const cell = self.float_cells_list.at(i);
                    self.game_field.set(cell, prob);
                }
                return self.game_field;
            }
        }

        var group_maps = try stl.map.vecmapvec64.new(groups.size);
        defer group_maps.free();

        var group: u8 = 0;
        while (group < groups.size) : (group += 1) {
            const pair = groups.at(group);
            const edge_cells = pair.first;
            const num_cells = pair.second;

            if (edge_cells.size > 128) {
                self.game_field.set(0, 20);
                return self.game_field;
            }

            var combs = try stl.map.mapvec64.new(edge_cells.size + 1);
            if (edge_cells.size <= LIMIT_BRUTE_FORCE) {
                try self.brute_force(&edge_cells, &num_cells, &combs);
            } else if (edge_cells.size <= 64) {
                try self.find_all_combinations64(&edge_cells, &num_cells, &combs);
            } else {
                try self.find_all_combinations128(&edge_cells, &num_cells, &combs);
            }
            group_maps.set(group, combs);
        }

        var occurrences_map = try stl.map.mapvec64.new(self.edge_cells_count + 1);
        defer occurrences_map.free();
        try self.create_occurrences_map(&group_maps, &occurrences_map);

        if (occurrences_map.empty()) {
            self.game_field.set(0, 22);
            return self.game_field;
        }

        try self.calculate_probabilities(&occurrences_map);

        return self.game_field;
    }
};
