const std = @import("std");
const simd = @import("simd.zig");

pub fn lexicographic(a: []const u8, b: []const u8) i8 {
    const len = @min(a.len, b.len);
    var i: usize = 0;
    const max_i = len -| simd.VEC_LEN;

    while (i < max_i) : (i += simd.VEC_LEN) {
        const a_vec: simd.VecU8 = a[i .. i + simd.VEC_LEN][0..simd.VEC_LEN].*;
        const b_vec: simd.VecU8 = b[i .. i + simd.VEC_LEN][0..simd.VEC_LEN].*;
        const mask: std.meta.Int(.unsigned, simd.VEC_LEN) = @bitCast(a_vec != b_vec);
        if (mask == 0) continue;

        const diff_index = i + @ctz(mask);
        if (a[diff_index] > b[diff_index]) return 1 else return -1;
    }

    while (i < len) : (i += 1) {
        if (a[i] > b[i]) {
            return 1;
        } else if (a[i] < b[i]) {
            return -1;
        }
    }

    if (a.len == b.len) {
        return 0;
    } else if (a.len > b.len) {
        return 1;
    } else {
        return -1;
    }
}

test "lexicographic" {
    const a = "abcdefghijklmnopqrstuzwxyz";
    const b = "abcdefghizzzzzzzzzzzzzzzzz";
    try std.testing.expectEqual(-1, lexicographic(a, b));

    const a_short = "apple";
    const b_short = "banana";
    try std.testing.expectEqual(-1, lexicographic(a_short, b_short));
}
