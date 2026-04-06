const std = @import("std");

pub const VEC_LEN = std.simd.suggestVectorLength(u8) orelse 4;
pub const VecU8 = @Vector(VEC_LEN, u8);
