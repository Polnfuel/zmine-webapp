const std = @import("std");
const stl = @import("stl");
const probs = @import("probs");

const wasm_allocator = std.heap.wasm_allocator;

export fn initModule(w: u8, h: u8, m: u16) bool {
    stl.set_alloc(wasm_allocator);
    probs.init(w, h, m) catch {
        return false;
    };
    return true;
}

export fn resizeModule(new_w: u8, new_h: u8, new_m: u16) bool {
    const result = probs.resize(new_w, new_h, new_m);
    if (result) |_| {
        return true;
    } else |_| {
        return false;
    }
}

export fn inputPtr() [*]u8 {
    return probs.get_input_ptr();
}

export fn inputLen() usize {
    return probs.get_input_len();
}

export fn fieldWidth() u8 {
    return probs.field_width;
}
export fn fieldHeight() u8 {
    return probs.field_height;
}
export fn totalMines() u16 {
    return probs.total_mines;
}

export fn probsCalc() bool {
    const result = probs.probs_field();
    if (result) |_| {
        return true;
    } else |_| {
        return false;
    }
}

export fn probsPtr() [*]u8 {
    return probs.get_probs_ptr();
}

export fn probsLen() usize {
    return probs.get_probs_len();
}

export fn deinitModule() void {
    probs.deinit();
}
