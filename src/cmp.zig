const std = @import("std");
const simd = @import("simd.zig");

inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

inline fn at(s: []const u8, i: usize) u8 {
    return if (i < s.len) s[i] else 0;
}

pub fn frac(a: []const u8, b: []const u8) i8 {
    return fracWithDecimal(a, b, '.');
}

fn fracWithDecimal(a: []const u8, b: []const u8, decimal_point: u8) i8 {
    var ia: usize = 0;
    var ib: usize = 0;
    const ca0 = at(a, ia);
    const cb0 = at(b, ib);

    if (ca0 == decimal_point and cb0 == decimal_point) {
        while (true) {
            ia += 1;
            ib += 1;
            const ca = at(a, ia);
            const cb = at(b, ib);
            if (ca != cb) break;
            if (!isDigit(ca)) return 0;
        }
        const ca = at(a, ia);
        const cb = at(b, ib);
        if (isDigit(ca) and isDigit(cb)) {
            return @truncate(@as(i16, ca) - cb);
        }
        if (isDigit(ca)) {
            return fracTrailingNonzero(a, ia);
        }
        if (isDigit(cb)) {
            return -fracTrailingNonzero(b, ib);
        }
        return 0;
    } else if (ca0 == decimal_point) {
        ia += 1;
        return fracTrailingNonzero(a, ia);
    } else if (cb0 == decimal_point) {
        ib += 1;
        return -fracTrailingNonzero(b, ib);
    }
    return 0;
}

fn fracTrailingNonzero(s: []const u8, start: usize) i8 {
    var i = start;
    while (at(s, i) == '0') i += 1;
    return if (isDigit(at(s, i))) 1 else 0;
}

fn skipLeadingZeros(s: []const u8, i: *usize) void {
    while (at(s, i.*) == '0') i.* += 1;
}

fn skipZerosAfterDot(s: []const u8, i: *usize, decimal_point: u8) void {
    if (at(s, i.*) != decimal_point) return;
    i.* += 1;
    while (at(s, i.*) == '0') i.* += 1;
}

/// Compare numeric strings without full parse (coreutils `numcompare`, no grouping separators).
pub fn numericWithDecimal(a: []const u8, b: []const u8, decimal_point: u8) i8 {
    var ia: usize = 0;
    var ib: usize = 0;
    var tmpa = at(a, ia);
    var tmpb = at(b, ib);
    var tmp: i16 = undefined;
    var log_a: usize = undefined;
    var log_b: usize = undefined;

    if (tmpa == '-') {
        ia += 1;
        skipLeadingZeros(a, &ia);
        tmpa = at(a, ia);

        if (tmpb != '-') {
            if (tmpa == decimal_point) skipZerosAfterDot(a, &ia, decimal_point);
            tmpa = at(a, ia);
            if (isDigit(tmpa)) return -1;

            skipLeadingZeros(b, &ib);
            tmpb = at(b, ib);
            if (tmpb == decimal_point) skipZerosAfterDot(b, &ib, decimal_point);
            tmpb = at(b, ib);
            return if (isDigit(tmpb)) -1 else 0;
        }

        ib += 1;
        skipLeadingZeros(b, &ib);
        tmpb = at(b, ib);

        while (tmpa == tmpb and isDigit(tmpa)) {
            ia += 1;
            tmpa = at(a, ia);
            ib += 1;
            tmpb = at(b, ib);
        }

        if ((tmpa == decimal_point and !isDigit(tmpb)) or
            (tmpb == decimal_point and !isDigit(tmpa)))
        {
            return fracWithDecimal(
                b[ib..],
                a[ia..],
                decimal_point,
            );
        }

        tmp = @as(i16, tmpb) - tmpa;

        log_a = 0;
        while (isDigit(tmpa)) : (log_a += 1) {
            ia += 1;
            tmpa = at(a, ia);
        }

        log_b = 0;
        while (isDigit(tmpb)) : (log_b += 1) {
            ib += 1;
            tmpb = at(b, ib);
        }

        if (log_a != log_b) {
            return if (log_a < log_b) 1 else -1;
        }
        if (log_a == 0) return 0;
        return @truncate(tmp);
    } else if (tmpb == '-') {
        ib += 1;
        skipLeadingZeros(b, &ib);
        tmpb = at(b, ib);
        if (tmpb == decimal_point) skipZerosAfterDot(b, &ib, decimal_point);
        tmpb = at(b, ib);
        if (isDigit(tmpb)) return 1;

        skipLeadingZeros(a, &ia);
        tmpa = at(a, ia);
        if (tmpa == decimal_point) skipZerosAfterDot(a, &ia, decimal_point);
        tmpa = at(a, ia);
        return if (isDigit(tmpa)) 1 else 0;
    } else {
        skipLeadingZeros(a, &ia);
        tmpa = at(a, ia);
        skipLeadingZeros(b, &ib);
        tmpb = at(b, ib);

        while (tmpa == tmpb and isDigit(tmpa)) {
            ia += 1;
            tmpa = at(a, ia);
            ib += 1;
            tmpb = at(b, ib);
        }

        if ((tmpa == decimal_point and !isDigit(tmpb)) or
            (tmpb == decimal_point and !isDigit(tmpa)))
        {
            return fracWithDecimal(a[ia..], b[ib..], decimal_point);
        }

        tmp = @as(i16, tmpa) - tmpb;

        log_a = 0;
        while (isDigit(tmpa)) : (log_a += 1) {
            ia += 1;
            tmpa = at(a, ia);
        }

        log_b = 0;
        while (isDigit(tmpb)) : (log_b += 1) {
            ib += 1;
            tmpb = at(b, ib);
        }

        if (log_a != log_b) {
            return if (log_a < log_b) -1 else 1;
        }
        if (log_a == 0) return 0;
        return @truncate(tmp);
    }
}

pub fn numeric(a: []const u8, b: []const u8) i8 {
    return numericWithDecimal(a, b, '.');
}

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

test "numeric" {
    try std.testing.expectEqual(-1, numeric("2", "10"));
    try std.testing.expectEqual(1, numeric("10", "2"));
    try std.testing.expectEqual(0, numeric("007", "7"));
    try std.testing.expectEqual(-1, numeric("-2", "1"));
    try std.testing.expectEqual(1, numeric("1", "-2"));
    try std.testing.expectEqual(-1, numeric("1.5", "1.6"));
    try std.testing.expectEqual(0, numeric("1.50", "1.5"));
}

test "frac" {
    try std.testing.expectEqual(-1, frac(".5", ".6"));
    try std.testing.expectEqual(0, frac(".50", ".5"));
    try std.testing.expectEqual(0, frac(".", "."));
}

test "numericWithDecimal" {
    try std.testing.expectEqual(0, numericWithDecimal("1,5", "1,5", ','));
    try std.testing.expectEqual(-1, numericWithDecimal("1,5", "1,6", ','));
}
